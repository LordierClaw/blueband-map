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

    let styleClient: VietmapStyleClient?
    let tileTransport: (any MapHTTPTransport)?
    let request: StaticMapRequest

    init(
        styleClient: VietmapStyleClient? = nil,
        tileTransport: (any MapHTTPTransport)? = nil,
        request: StaticMapRequest = M1Configuration.request
    ) {
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
        case .rasterStaticCompact:
            let scene = try await makeVietmapScene(tileMapKey: tileMapKey, maximumSegments: 80)
            return try RenderAsset(
                kind: .raster,
                formatVersion: RenderProtocol.formatVersion,
                width: RenderProtocol.viewportWidth,
                height: RenderProtocol.viewportHeight,
                data: IndexedPNGEncoder.encode(try IndexedRaster.render(scene: scene)),
                primitives: 0
            )

        case .rasterTileMap:
            let scene = try await makeVietmapScene(tileMapKey: tileMapKey, maximumSegments: 200)
            return try RenderAsset(
                kind: .raster,
                formatVersion: RenderProtocol.formatVersion,
                width: RenderProtocol.viewportWidth,
                height: RenderProtocol.viewportHeight,
                data: IndexedPNGEncoder.encode(try IndexedRaster.render(scene: scene)),
                primitives: 0
            )

        case .vectorTileMap40, .vectorTileMap60:
            return try makeVectorAsset(try await makeVietmapScene(
                tileMapKey: tileMapKey,
                maximumSegments: mode.expectedPrimitives
            ))
        }
    }

    private func makeVietmapScene(tileMapKey: String?, maximumSegments: Int) async throws -> NavigationScene {
        guard let tileMapKey, let styleClient, let tileTransport else {
            throw Error.missingTileMapConfiguration
        }
        let template = try await styleClient.discover(tileMapKey: tileMapKey)
        let displayZoom = max(0, request.zoom - 1)
        let tileZoom = Self.clampedZoom(displayZoom, template: template)
        let coordinates = Self.tileCoordinates(
            latitude: request.latitude,
            longitude: request.longitude,
            displayZoom: displayZoom,
            tileZoom: tileZoom
        )
        let tiles = try await withThrowingTaskGroup(of: VietmapSceneTile.self) { group in
            for coordinate in coordinates {
                group.addTask {
                    let tileURL = try template.url(
                        z: tileZoom,
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
                    guard response.statusCode == 200 else { throw Error.tileHTTPStatus(response.statusCode) }
                    guard Self.isVectorTileContentType(response.header(named: "Content-Type"), url: tileURL) else {
                        throw Error.tileWrongContentType
                    }
                    guard !response.body.isEmpty else { throw Error.tileEmpty }
                    return VietmapSceneTile(
                        tile: try VietmapVectorTileDecoder.decode(response.body),
                        zoom: tileZoom,
                        x: coordinate.x,
                        y: coordinate.y
                    )
                }
            }
            var result = [VietmapSceneTile]()
            for try await tile in group { result.append(tile) }
            return result.sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
        }
        let scene = try VietmapSceneBuilder.build(
            tiles: tiles,
            sourceLayers: Set(template.sourceLayers),
            latitude: request.latitude,
            longitude: request.longitude,
            displayZoom: displayZoom,
            headingDegrees: 0,
            maneuver: .straight,
            distanceMeters: 0,
            maximumSegments: maximumSegments
        )
        guard !scene.segments.isEmpty else { throw Error.tileHasNoRoads }
        return scene
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

    private static func tileCoordinates(
        latitude: Double,
        longitude: Double,
        displayZoom: Int,
        tileZoom: Int
    ) -> [(x: Int, y: Int)] {
        let displayCount = 1 << displayZoom
        let tileCount = 1 << tileZoom
        let worldWidth = Double(displayCount * 256)
        let centerX = (longitude + 180) / 360 * worldWidth
        let safeLatitude = min(max(latitude, -85.05112878), 85.05112878)
        let radians = safeLatitude * .pi / 180
        let centerY = (1 - log(tan(radians) + 1 / cos(radians)) / .pi) / 2 * worldWidth
        let overscale = pow(2, Double(displayZoom - tileZoom))
        let minimumX = Int(floor((centerX - Double(RenderProtocol.viewportWidth) / 2) / overscale / 256))
        let maximumX = Int(floor((centerX + Double(RenderProtocol.viewportWidth) / 2) / overscale / 256))
        let minimumY = Int(floor((centerY - Double(RenderProtocol.viewportHeight) / 2) / overscale / 256))
        let maximumY = Int(floor((centerY + Double(RenderProtocol.viewportHeight) / 2) / overscale / 256))
        return (minimumY...maximumY).flatMap { y in
            (minimumX...maximumX).map { x in
                (max(0, min(tileCount - 1, x)), max(0, min(tileCount - 1, y)))
            }
        }
    }

    private static func clampedZoom(_ requestedZoom: Int, template: VectorTileTemplate) -> Int {
        var zoom = requestedZoom
        if let minimumZoom = template.minimumZoom { zoom = max(zoom, minimumZoom) }
        if let maximumZoom = template.maximumZoom { zoom = min(zoom, maximumZoom) }
        return zoom
    }

    private static func isVectorTileContentType(_ value: String?, url: URL) -> Bool {
        let isTrustedVectorTile = url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "maps.vietmap.vn"
            && url.user == nil
            && url.password == nil
            && (url.path.lowercased().hasSuffix(".pbf") || isLegacyVietmapTilePath(url.path))
        guard let value else { return isTrustedVectorTile }
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
        return mediaType == "text/plain" && isTrustedVectorTile
    }

    private static func isLegacyVietmapTilePath(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 6,
              components[0] == "mt",
              components[1] == "tile",
              components[2].hasPrefix("data-"),
              !components[2].dropFirst("data-".count).isEmpty else {
            return false
        }
        return components[3...5].allSatisfy { Int($0) != nil }
    }
}
