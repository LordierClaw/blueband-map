import Foundation

public enum VietmapSceneBuilder {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidRequest
        case invalidHeading
    }

    private struct RankedSegment {
        let rank: Int
        let distanceSquared: Int
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
        distanceMeters: UInt32,
        maximumSegments: Int = RenderProtocol.maximumPrimitives
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
            distanceMeters: distanceMeters,
            maximumSegments: maximumSegments
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
        distanceMeters: UInt32,
        maximumSegments: Int = RenderProtocol.maximumPrimitives
    ) throws -> NavigationScene {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude),
              (0...22).contains(zoom), headingDegrees >= 0, headingDegrees <= 359,
              !tiles.isEmpty,
              (1...NavigationScene.maximumSegments).contains(maximumSegments) else {
            throw Error.invalidRequest
        }

        var ranked = [RankedSegment]()
        var order = 0
        for tile in tiles {
            for layer in tile.layers where sourceLayers == nil || sourceLayers?.contains(layer.name) == true {
                for feature in layer.features where feature.geometryType == .lineString {
                    guard let lineClass = classify(feature.properties) else { continue }
                    let rank = lineClass == .route ? 0 : (lineClass == .major ? 1 : 2)
                    for line in feature.lines {
                        guard line.count >= 2 else { continue }
                        var projected = [SceneSegment]()
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
                            projected.append(segment)
                        }
                        for segment in simplify(projected) {
                            let centerX = RenderProtocol.viewportWidth / 2
                            let centerY = RenderProtocol.viewportHeight / 2
                            let midpointX = (Int(segment.start.x) + Int(segment.end.x)) / 2
                            let midpointY = (Int(segment.start.y) + Int(segment.end.y)) / 2
                            let dx = midpointX - centerX
                            let dy = midpointY - centerY
                            ranked.append(RankedSegment(
                                rank: rank,
                                distanceSquared: dx * dx + dy * dy,
                                order: order,
                                segment: segment
                            ))
                            order += 1
                        }
                    }
                }
            }
        }

        var remaining = ranked
            .sorted { left, right in
                if (left.rank == 0) != (right.rank == 0) { return left.rank == 0 }
                if left.distanceSquared != right.distanceSquared {
                    return left.distanceSquared < right.distanceSquared
                }
                if left.rank != right.rank { return left.rank < right.rank }
                return left.order < right.order
            }
        var selected = [RankedSegment]()
        while !remaining.isEmpty && selected.count < maximumSegments {
            let index = selected.isEmpty ? 0 : remaining.firstIndex { candidate in
                selected.contains { connects($0.segment, candidate.segment) }
            } ?? 0
            selected.append(remaining.remove(at: index))
        }
        let segments = magnify(selected.map(\.segment))

        return try NavigationScene(
            currentPosition: ScenePoint(
                x: UInt16(RenderProtocol.viewportWidth / 2),
                y: UInt16(RenderProtocol.viewportHeight / 2)
            ),
            headingDegrees: UInt16(headingDegrees),
            maneuver: maneuver,
            distanceMeters: distanceMeters,
            segments: segments
        )
    }

    private static func simplify(_ segments: [SceneSegment]) -> [SceneSegment] {
        var result = [SceneSegment]()
        for segment in segments {
            if let previous = result.last,
               previous.end == segment.start,
               areNearlyStraight(previous, segment) {
                result[result.count - 1] = SceneSegment(
                    start: previous.start,
                    end: segment.end,
                    lineClass: previous.lineClass
                )
            } else {
                result.append(segment)
            }
        }
        return result
    }

    private static func areNearlyStraight(_ first: SceneSegment, _ second: SceneSegment) -> Bool {
        let firstX = Int(first.end.x) - Int(first.start.x)
        let firstY = Int(first.end.y) - Int(first.start.y)
        let secondX = Int(second.end.x) - Int(second.start.x)
        let secondY = Int(second.end.y) - Int(second.start.y)
        let dot = firstX * secondX + firstY * secondY
        let cross = abs(firstX * secondY - firstY * secondX)
        let longest = max(abs(firstX), abs(firstY), abs(secondX), abs(secondY))
        return dot > 0 && cross <= max(2, longest * 2)
    }

    private static func connects(_ left: SceneSegment, _ right: SceneSegment) -> Bool {
        left.start == right.start || left.start == right.end ||
            left.end == right.start || left.end == right.end
    }

    private static func magnify(_ segments: [SceneSegment]) -> [SceneSegment] {
        guard segments.count >= 8 else { return segments }
        let centerX = RenderProtocol.viewportWidth / 2
        let centerY = RenderProtocol.viewportHeight / 2
        let points = segments.flatMap { [$0.start, $0.end] }
        let maxDX = max(1, points.map { abs(Int($0.x) - centerX) }.max() ?? 1)
        let maxDY = max(1, points.map { abs(Int($0.y) - centerY) }.max() ?? 1)
        let scale = min(
            3.5,
            Double(min(centerX, RenderProtocol.viewportWidth - 1 - centerX) - 6) / Double(maxDX),
            Double(min(centerY, RenderProtocol.viewportHeight - 1 - centerY) - 6) / Double(maxDY)
        )
        guard scale > 1 else { return segments }

        func point(_ source: ScenePoint) -> ScenePoint {
            ScenePoint(
                x: UInt16((Double(Int(source.x) - centerX) * scale).rounded() + Double(centerX)),
                y: UInt16((Double(Int(source.y) - centerY) * scale).rounded() + Double(centerY))
            )
        }
        return segments.map {
            SceneSegment(start: point($0.start), end: point($0.end), lineClass: $0.lineClass)
        }
    }

    private static func classify(_ properties: [String: String]) -> SceneLineClass? {
        let values = properties
            .filter { ["class", "road_class", "highway", "kind", "type"].contains($0.key.lowercased()) }
            .map { $0.value.lowercased() }
        if values.contains("path") { return nil }
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
