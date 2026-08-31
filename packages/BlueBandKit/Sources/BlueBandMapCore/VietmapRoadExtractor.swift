import Foundation

public struct VietmapSceneTile: Equatable, Sendable {
    public let tile: MapboxVectorTile
    public let zoom: Int
    public let x: Int
    public let y: Int

    public init(tile: MapboxVectorTile, zoom: Int, x: Int, y: Int) {
        self.tile = tile
        self.zoom = zoom
        self.x = x
        self.y = y
    }
}

public enum VietmapRoadExtractor {
    public static func extract(tiles: [VietmapSceneTile], sourceLayers: Set<String>) -> [RoadPolyline] {
        tiles.flatMap { source in
            source.tile.layers
                .filter { sourceLayers.contains($0.name) }
                .flatMap { layer in
                    layer.features.compactMap { feature -> [RoadPolyline]? in
                        guard feature.geometryType == .lineString,
                              let major = roadClass(feature.properties) else { return nil }
                        return feature.lines.compactMap { line in
                            guard line.count >= 2 else { return nil }
                            return RoadPolyline(
                                points: line.map { coordinate($0, extent: layer.extent, tile: source) },
                                isMajor: major
                            )
                        }
                    }.flatMap { $0 }
                }
        }
    }

    private static func roadClass(_ properties: [String: String]) -> Bool? {
        let values = properties
            .filter { ["class", "road_class", "highway", "kind", "type"].contains($0.key.lowercased()) }
            .map { $0.value.lowercased() }
        guard !values.contains(where: { $0.contains("path") || $0.contains("rail") }) else { return nil }
        return values.contains(where: {
            ["motorway", "trunk", "primary", "secondary", "tertiary", "highway", "major"].contains($0)
        })
    }

    private static func coordinate(
        _ point: MapboxVectorTile.TilePoint,
        extent: Int,
        tile: VietmapSceneTile
    ) -> GeoPoint {
        let tileCount = pow(2, Double(tile.zoom))
        let worldX = (Double(tile.x) + Double(point.x) / Double(extent)) / tileCount
        let worldY = (Double(tile.y) + Double(point.y) / Double(extent)) / tileCount
        return GeoPoint(
            latitude: atan(sinh(.pi * (1 - 2 * worldY))) * 180 / .pi,
            longitude: worldX * 360 - 180
        )
    }
}
