import Foundation
import BlueBandMapCore

struct H1AssetFactory: Sendable {
    enum Error: Swift.Error, Equatable, Sendable {
        case missingTileMapConfiguration
        case tileHTTPStatus(Int)
        case tileWrongContentType
        case tileEmpty
        case tileHasNoRoads
    }

    let staticMapProvider: any StaticMapProviding
    let styleClient: VietmapStyleClient?
    let tileTransport: (any MapHTTPTransport)?
    let request: StaticMapRequest

    init(
        staticMapProvider: any StaticMapProviding,
        styleClient: VietmapStyleClient? = nil,
        tileTransport: (any MapHTTPTransport)? = nil,
        request: StaticMapRequest = M1Configuration.request
    ) {
        self.staticMapProvider = staticMapProvider
        self.styleClient = styleClient
        self.tileTransport = tileTransport
        self.request = request
    }

    var provider: H1AssetProvider {
        { mode, serviceKey, tileMapKey in
            try await self.make(mode: mode, serviceKey: serviceKey, tileMapKey: tileMapKey)
        }
    }

    func make(
        mode: H1TestMode,
        serviceKey: String?,
        tileMapKey: String?
    ) async throws -> RenderAsset {
        switch mode {
        case .rasterBaseline:
            guard let serviceKey else { throw VietmapStaticMapError.missingServiceKey }
            let map = try await staticMapProvider.fetch(request, serviceKey: serviceKey)
            return try RenderAsset(
                kind: .raster,
                formatVersion: RenderProtocol.formatVersion,
                width: map.width,
                height: map.height,
                data: map.data,
                primitives: 0
            )

        case .rasterOptimized:
            let scene = try NavigationScene.synthetic(segmentCount: 20)
            let raster = try IndexedRaster.render(scene: scene)
            let png = try IndexedPNGEncoder.encode(raster)
            return try RenderAsset(
                kind: .raster,
                formatVersion: RenderProtocol.formatVersion,
                width: raster.width,
                height: raster.height,
                data: png,
                primitives: 0
            )

        case .vectorSynthetic8, .vectorSynthetic20, .vectorSynthetic40:
            let scene = try NavigationScene.synthetic(segmentCount: mode.expectedPrimitives)
            return try makeVectorAsset(scene)

        case .vectorVietmap:
            guard let tileMapKey, let styleClient, let tileTransport else {
                throw Error.missingTileMapConfiguration
            }
            let template = try await styleClient.discover(tileMapKey: tileMapKey)
            let zoom = Self.clampedZoom(request.zoom, template: template)
            let coordinate = Self.tileCoordinate(
                latitude: request.latitude,
                longitude: request.longitude,
                zoom: zoom
            )
            let tileURL = try template.url(
                z: zoom,
                x: coordinate.x,
                y: coordinate.y,
                tileMapKey: tileMapKey
            )
            let response = try await tileTransport.execute(MapHTTPRequest(
                method: "GET",
                url: tileURL,
                headers: [
                    "Accept": "application/vnd.mapbox-vector-tile, application/x-protobuf, application/octet-stream",
                ],
                body: Data(),
                maximumResponseBytes: MapboxVectorTile.maximumBodyBytes
            ))
            guard response.statusCode == 200 else {
                throw Error.tileHTTPStatus(response.statusCode)
            }
            guard Self.isVectorTileContentType(
                response.header(named: "Content-Type"),
                url: tileURL
            ) else {
                throw Error.tileWrongContentType
            }
            guard !response.body.isEmpty else { throw Error.tileEmpty }
            let tile = try MapboxVectorTile.decode(response.body)
            let scene = try VietmapSceneBuilder.build(
                tile: tile,
                latitude: request.latitude,
                longitude: request.longitude,
                zoom: zoom,
                tileX: coordinate.x,
                tileY: coordinate.y,
                headingDegrees: 0,
                maneuver: .straight,
                distanceMeters: 0
            )
            guard !scene.segments.isEmpty else { throw Error.tileHasNoRoads }
            return try makeVectorAsset(scene)
        }
    }

    private func makeVectorAsset(_ scene: NavigationScene) throws -> RenderAsset {
        try RenderAsset(
            kind: .vector,
            formatVersion: RenderProtocol.formatVersion,
            width: RenderProtocol.viewportWidth,
            height: RenderProtocol.viewportHeight,
            data: VectorSceneCodec.encode(scene),
            primitives: scene.segments.count
        )
    }

    private static func tileCoordinate(
        latitude: Double,
        longitude: Double,
        zoom: Int
    ) -> (x: Int, y: Int) {
        let count = 1 << zoom
        let x = Int(floor((longitude + 180) / 360 * Double(count)))
        let safeLatitude = min(max(latitude, -85.05112878), 85.05112878)
        let radians = safeLatitude * .pi / 180
        let y = Int(floor(
            (1 - log(tan(radians) + 1 / cos(radians)) / .pi) / 2 * Double(count)
        ))
        return (
            max(0, min(count - 1, x)),
            max(0, min(count - 1, y))
        )
    }

    private static func clampedZoom(_ requestedZoom: Int, template: VectorTileTemplate) -> Int {
        var zoom = requestedZoom
        if let minimumZoom = template.minimumZoom { zoom = max(zoom, minimumZoom) }
        if let maximumZoom = template.maximumZoom { zoom = min(zoom, maximumZoom) }
        return zoom
    }

    private static func isVectorTileContentType(_ value: String?, url: URL) -> Bool {
        guard let value else { return false }
        let mediaType = value
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if [
            "application/vnd.mapbox-vector-tile",
            "application/x-protobuf",
            "application/octet-stream",
        ].contains(mediaType) {
            return true
        }
        return mediaType == "text/plain"
            && url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "maps.vietmap.vn"
            && url.user == nil
            && url.password == nil
            && url.path.lowercased().hasSuffix(".pbf")
    }
}
