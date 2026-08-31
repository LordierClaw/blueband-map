import Foundation

public enum VietmapSceneBuilder {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidRequest
        case invalidHeading
    }

    private struct RankedSegment {
        let rank: Int
        let order: Int
        let segment: SceneSegment
    }

    public static func build(
        tile: MapboxVectorTile,
        sourceLayers: Set<String>? = nil,
        latitude: Double,
        longitude: Double,
        zoom: Int,
        tileX: Int,
        tileY: Int,
        headingDegrees: Int,
        maneuver: ManeuverKind,
        distanceMeters: UInt32
    ) throws -> NavigationScene {
        try build(
            tiles: [tile],
            sourceLayers: sourceLayers,
            latitude: latitude,
            longitude: longitude,
            zoom: zoom,
            tileX: tileX,
            tileY: tileY,
            headingDegrees: headingDegrees,
            maneuver: maneuver,
            distanceMeters: distanceMeters
        )
    }

    public static func build(
        tiles: [MapboxVectorTile],
        sourceLayers: Set<String>? = nil,
        latitude: Double,
        longitude: Double,
        zoom: Int,
        tileX: Int,
        tileY: Int,
        headingDegrees: Int,
        maneuver: ManeuverKind,
        distanceMeters: UInt32
    ) throws -> NavigationScene {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude),
              (0...22).contains(zoom), headingDegrees >= 0, headingDegrees <= 359,
              !tiles.isEmpty else {
            throw Error.invalidRequest
        }

        var ranked = [RankedSegment]()
        var order = 0
        for tile in tiles {
            for layer in tile.layers where sourceLayers == nil || sourceLayers?.contains(layer.name) == true {
                for feature in layer.features where feature.geometryType == .lineString {
                    let lineClass = classify(feature.properties)
                    let rank = lineClass == .route ? 0 : (lineClass == .major ? 1 : 2)
                    for line in feature.lines {
                        guard line.count >= 2 else { continue }
                        for pair in zip(line, line.dropFirst()) {
                            guard let segment = projectAndClip(
                                start: pair.0,
                                end: pair.1,
                                extent: layer.extent,
                                latitude: latitude,
                                longitude: longitude,
                                zoom: zoom,
                                tileX: tileX,
                                tileY: tileY,
                                lineClass: lineClass
                            ) else { continue }
                            ranked.append(RankedSegment(rank: rank, order: order, segment: segment))
                            order += 1
                        }
                    }
                }
            }
        }

        let selected = ranked
            .sorted { left, right in
                left.rank == right.rank ? left.order < right.order : left.rank < right.rank
            }
            .prefix(NavigationScene.maximumSegments)
            .map(\.segment)

        return try NavigationScene(
            currentPosition: ScenePoint(
                x: UInt16(RenderProtocol.viewportWidth / 2),
                y: UInt16(RenderProtocol.viewportHeight / 2)
            ),
            headingDegrees: UInt16(headingDegrees),
            maneuver: maneuver,
            distanceMeters: distanceMeters,
            segments: Array(selected)
        )
    }

    private static func classify(_ properties: [String: String]) -> SceneLineClass {
        let values = properties
            .filter { ["class", "road_class", "highway", "kind", "type"].contains($0.key.lowercased()) }
            .map { $0.value.lowercased() }
        if values.contains(where: { $0.contains("route") || $0.contains("navigation") }) { return .route }
        if values.contains(where: {
            ["motorway", "trunk", "primary", "secondary", "tertiary", "highway", "major"].contains($0)
        }) { return .major }
        return .minor
    }

    private static func projectAndClip(
        start: MapboxVectorTile.TilePoint,
        end: MapboxVectorTile.TilePoint,
        extent: Int,
        latitude: Double,
        longitude: Double,
        zoom: Int,
        tileX: Int,
        tileY: Int,
        lineClass: SceneLineClass
    ) -> SceneSegment? {
        let scale = pow(2, Double(zoom))
        let tileSize = 256.0
        let extentScale = tileSize / Double(extent)
        let worldWidth = scale * tileSize
        let safeLatitude = min(max(latitude, -85.05112878), 85.05112878)
        let sine = sin(safeLatitude * .pi / 180)
        let centerX = (longitude + 180) / 360 * worldWidth
        let centerY = (0.5 - log((1 + sine) / (1 - sine)) / (4 * .pi)) * worldWidth
        let startWorld = (
            Double(tileX) * tileSize + Double(start.x) * extentScale,
            Double(tileY) * tileSize + Double(start.y) * extentScale
        )
        let endWorld = (
            Double(tileX) * tileSize + Double(end.x) * extentScale,
            Double(tileY) * tileSize + Double(end.y) * extentScale
        )
        var x0 = startWorld.0 - centerX + Double(RenderProtocol.viewportWidth / 2)
        var y0 = startWorld.1 - centerY + Double(RenderProtocol.viewportHeight / 2)
        var x1 = endWorld.0 - centerX + Double(RenderProtocol.viewportWidth / 2)
        var y1 = endWorld.1 - centerY + Double(RenderProtocol.viewportHeight / 2)
        guard clip(&x0, &y0, &x1, &y1, minX: 0, maxX: Double(RenderProtocol.viewportWidth - 1), minY: 0, maxY: Double(RenderProtocol.viewportHeight - 1)) else {
            return nil
        }

        let startPoint = ScenePoint(
            x: UInt16(max(0, min(RenderProtocol.viewportWidth - 1, Int(x0.rounded())))),
            y: UInt16(max(0, min(RenderProtocol.viewportHeight - 1, Int(y0.rounded()))))
        )
        let endPoint = ScenePoint(
            x: UInt16(max(0, min(RenderProtocol.viewportWidth - 1, Int(x1.rounded())))),
            y: UInt16(max(0, min(RenderProtocol.viewportHeight - 1, Int(y1.rounded()))))
        )
        guard startPoint != endPoint else { return nil }
        return SceneSegment(start: startPoint, end: endPoint, lineClass: lineClass)
    }

    private static func clip(
        _ x0: inout Double,
        _ y0: inout Double,
        _ x1: inout Double,
        _ y1: inout Double,
        minX: Double,
        maxX: Double,
        minY: Double,
        maxY: Double
    ) -> Bool {
        let dx = x1 - x0
        let dy = y1 - y0
        var lower = 0.0
        var upper = 1.0
        let boundaries = [
            (-dx, x0 - minX),
            (dx, maxX - x0),
            (-dy, y0 - minY),
            (dy, maxY - y0),
        ]
        for (p, q) in boundaries {
            if p == 0 {
                if q < 0 { return false }
                continue
            }
            let ratio = q / p
            if p < 0 {
                if ratio > upper { return false }
                if ratio > lower { lower = ratio }
            } else {
                if ratio < lower { return false }
                if ratio < upper { upper = ratio }
            }
        }
        let originalX0 = x0
        let originalY0 = y0
        x0 = originalX0 + lower * dx
        y0 = originalY0 + lower * dy
        x1 = originalX0 + upper * dx
        y1 = originalY0 + upper * dy
        return true
    }
}
