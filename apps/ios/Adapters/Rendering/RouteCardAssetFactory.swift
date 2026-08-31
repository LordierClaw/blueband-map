import Foundation
import BlueBandMapCore

struct RouteCardAssetResult: Sendable {
    let asset: RenderAsset
    let scene: RouteCardScene
    let limitedMap: Bool
}

actor RouteCardTileCache {
    private var style: VectorTileTemplate?
    private var tiles: [URL: VietmapSceneTile] = [:]
    private var order: [URL] = []

    func cachedStyle() -> VectorTileTemplate? { style }
    func store(style: VectorTileTemplate) { self.style = style }
    func tile(for url: URL) -> VietmapSceneTile? { tiles[url] }
    func store(tile: VietmapSceneTile, for url: URL) {
        if tiles[url] == nil { order.append(url) }
        tiles[url] = tile
        while order.count > 16, let oldest = order.first {
            order.removeFirst()
            tiles.removeValue(forKey: oldest)
        }
    }
}

struct RouteCardAssetFactory: Sendable {
    enum Error: Swift.Error, Equatable, Sendable {
        case tileHTTPStatus(Int)
        case tileWrongContentType
        case tileEmpty
        case payloadTooLarge
    }

    let styleClient: VietmapStyleClient
    let tileTransport: any MapHTTPTransport
    let cache: RouteCardTileCache

    init(
        styleClient: VietmapStyleClient,
        tileTransport: any MapHTTPTransport,
        cache: RouteCardTileCache = RouteCardTileCache()
    ) {
        self.styleClient = styleClient
        self.tileTransport = tileTransport
        self.cache = cache
    }

    func make(input: RouteCardRenderInput, tileMapKey: String) async throws -> RouteCardAssetResult {
        let roads: [RoadPolyline]
        let limitedMap: Bool
        if tileMapKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            roads = []
            limitedMap = true
        } else {
            do {
                roads = try await loadRoads(near: input.route.points[input.progressIndex], tileMapKey: tileMapKey)
                limitedMap = false
            } catch {
                roads = []
                limitedMap = true
            }
        }
        let maximumSideRoads = min(12, roads.count)
        for count in stride(from: maximumSideRoads, through: 0, by: -1) {
            let tolerances = count == 0 ? [0, 1, 2, 3, 4, 6, 8, 12] : [0]
            for tolerance in tolerances {
                let scene = try RouteCardBuilder.build(
                    route: input.route,
                    progressIndex: input.progressIndex,
                    sideRoads: roads,
                    simplificationTolerance: tolerance,
                    sideRoadLimit: count
                )
                do {
                    let png = try IndexedPNGEncoder.encode(try IndexedRaster.render(routeCard: scene))
                    return RouteCardAssetResult(
                        asset: try RenderAsset(
                            kind: .raster,
                            formatVersion: RenderProtocol.formatVersion,
                            width: RenderProtocol.viewportWidth,
                            height: RenderProtocol.viewportHeight,
                            data: png,
                            primitives: 0
                        ),
                        scene: scene,
                        limitedMap: limitedMap
                    )
                } catch IndexedPNGEncoder.Error.payloadTooLarge {
                    continue
                }
            }
        }
        throw Error.payloadTooLarge
    }

    private func loadRoads(near point: GeoPoint, tileMapKey: String) async throws -> [RoadPolyline] {
        let template: VectorTileTemplate
        if let cached = await cache.cachedStyle() {
            template = cached
        } else {
            template = try await styleClient.discover(tileMapKey: tileMapKey)
            await cache.store(style: template)
        }
        let zoom = min(17, template.maximumZoom ?? 17)
        let center = Self.tileCoordinate(point, zoom: zoom)
        let tileCount = 1 << zoom
        var sourceTiles = [VietmapSceneTile]()
        var missing: [(url: URL, x: Int, y: Int)] = []
        for y in max(0, center.y - 1)...min(tileCount - 1, center.y + 1) {
            for x in max(0, center.x - 1)...min(tileCount - 1, center.x + 1) {
                let url = try template.url(z: zoom, x: x, y: y, tileMapKey: tileMapKey)
                if let cached = await cache.tile(for: url) {
                    sourceTiles.append(cached)
                    continue
                }
                missing.append((url, x, y))
            }
        }
        let transport = tileTransport
        try await withThrowingTaskGroup(of: (URL, VietmapSceneTile).self) { group in
            for request in missing {
                group.addTask {
                    let response = try await transport.execute(MapHTTPRequest(
                        method: "GET",
                        url: request.url,
                        headers: ["Accept": "application/vnd.mapbox-vector-tile, application/x-protobuf, application/octet-stream"],
                        body: Data(),
                        maximumResponseBytes: MapboxVectorTile.maximumBodyBytes
                    ))
                    guard response.statusCode == 200 else { throw Error.tileHTTPStatus(response.statusCode) }
                    guard Self.isVectorTile(response.header(named: "Content-Type")) else { throw Error.tileWrongContentType }
                    guard !response.body.isEmpty else { throw Error.tileEmpty }
                    return (
                        request.url,
                        VietmapSceneTile(
                            tile: try VietmapVectorTileDecoder.decode(response.body),
                            zoom: zoom,
                            x: request.x,
                            y: request.y
                        )
                    )
                }
            }
            for try await (url, tile) in group {
                await cache.store(tile: tile, for: url)
                sourceTiles.append(tile)
            }
        }
        return VietmapRoadExtractor.extract(tiles: sourceTiles, sourceLayers: Set(template.sourceLayers))
    }

    private static func tileCoordinate(_ point: GeoPoint, zoom: Int) -> (x: Int, y: Int) {
        let count = Double(1 << zoom)
        let latitude = min(max(point.latitude, -85.05112878), 85.05112878) * .pi / 180
        return (
            Int(floor((point.longitude + 180) / 360 * count)),
            Int(floor((1 - log(tan(latitude) + 1 / cos(latitude)) / .pi) / 2 * count))
        )
    }

    private static func isVectorTile(_ value: String?) -> Bool {
        guard let value else { return true }
        let mediaType = value.split(separator: ";", maxSplits: 1)[0].lowercased()
        return ["application/vnd.mapbox-vector-tile", "application/x-protobuf", "application/octet-stream", "text/plain"]
            .contains(String(mediaType))
    }
}
