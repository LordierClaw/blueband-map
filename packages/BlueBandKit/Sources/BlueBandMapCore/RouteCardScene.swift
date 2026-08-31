import Foundation

public struct RoadPolyline: Equatable, Sendable {
    public let points: [GeoPoint]
    public let isMajor: Bool
    public init(points: [GeoPoint], isMajor: Bool) { self.points = points; self.isMajor = isMajor }
}

public struct ScreenPoint: Equatable, Sendable {
    public let x: Int
    public let y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
}

public struct ScreenPolyline: Equatable, Sendable {
    public let points: [ScreenPoint]
    public let isMajor: Bool
    public init(points: [ScreenPoint], isMajor: Bool = false) { self.points = points; self.isMajor = isMajor }
}

public struct RouteCardScene: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let sideRoads: [ScreenPolyline]
    public let traveledRoute: [ScreenPolyline]
    public let upcomingRoute: [ScreenPolyline]
    public let marker: ScreenPoint
    public let maneuverPoint: ScreenPoint
    public let maneuver: NavigationManeuver
    public let distanceMeters: Int
    public let streetName: String

    public init(
        width: Int = RenderProtocol.viewportWidth,
        height: Int = RenderProtocol.viewportHeight,
        sideRoads: [ScreenPolyline],
        traveledRoute: [ScreenPolyline],
        upcomingRoute: [ScreenPolyline],
        marker: ScreenPoint,
        maneuverPoint: ScreenPoint,
        maneuver: NavigationManeuver,
        distanceMeters: Int,
        streetName: String
    ) {
        self.width = width
        self.height = height
        self.sideRoads = sideRoads
        self.traveledRoute = traveledRoute
        self.upcomingRoute = upcomingRoute
        self.marker = marker
        self.maneuverPoint = maneuverPoint
        self.maneuver = maneuver
        self.distanceMeters = distanceMeters
        self.streetName = streetName
    }
}

public enum RouteCardBuilder {
    public enum Error: Swift.Error, Equatable, Sendable { case invalidRoute, invalidProgress }
    private static let anchorMarker = ScreenPoint(x: 106, y: 320)

    public static func build(
        route: RoutePlan,
        progressIndex: Int,
        sideRoads: [RoadPolyline],
        simplificationTolerance: Int = 0,
        sideRoadLimit: Int = 12
    ) throws -> RouteCardScene {
        guard route.points.count >= 2, route.points.allSatisfy(\.isValid) else { throw Error.invalidRoute }
        guard route.points.indices.contains(progressIndex) else { throw Error.invalidProgress }
        let endIndex = forwardEnd(route.points, from: progressIndex, maximumMeters: 600)
        let startIndex = backwardStart(route.points, from: progressIndex, maximumMeters: 30)
        let visibleRoute = Array(route.points[startIndex...endIndex])
        guard visibleRoute.count >= 2 else { throw Error.invalidRoute }
        let headingTarget = route.points[min(progressIndex + 1, route.points.count - 1)]
        let transform = Transform(origin: route.points[progressIndex], headingTarget: headingTarget, points: visibleRoute)
        let projectedRoute = visibleRoute.map(transform.project)
        let currentOffset = progressIndex - startIndex
        let traveledPoints = simplify(Array(projectedRoute[...currentOffset]), tolerance: simplificationTolerance)
        let upcomingPoints = simplify(Array(projectedRoute[currentOffset...]), tolerance: simplificationTolerance)

        let instruction = route.instructions.first { $0.interval.upperBound >= progressIndex }
        let maneuverIndex = min(max(instruction?.interval.lowerBound ?? endIndex, startIndex), endIndex) - startIndex
        let maneuverPoint = projectedRoute[maneuverIndex]
        let routeReference = projectedRoute
        let rankedRoads = sideRoads.compactMap { road -> (Int, ScreenPolyline)? in
            guard road.points.count >= 2 else { return nil }
            let points = road.points.map(transform.projectUnclamped)
            let distance = points.map { point in
                zip(routeReference, routeReference.dropFirst()).map { pointSegmentDistance(point, $0, $1) }.min() ?? .infinity
            }.min() ?? .infinity
            guard distance <= 40 else { return nil }
            let maneuverDistance = points.map {
                hypot(Double($0.x - maneuverPoint.x), Double($0.y - maneuverPoint.y))
            }.min() ?? .infinity
            let clipped = points.map { ScreenPoint(x: min(211, max(0, $0.x)), y: min(359, max(0, $0.y))) }
            guard Set(clipped.map { "\($0.x),\($0.y)" }).count >= 2 else { return nil }
            let rank = Int(distance.rounded()) * 100_000 + (road.isMajor ? 0 : 50_000) + Int(maneuverDistance.rounded())
            return (rank, ScreenPolyline(points: clipped, isMajor: road.isMajor))
        }.sorted { $0.0 < $1.0 }.prefix(max(0, min(12, sideRoadLimit))).map(\.1)

        return RouteCardScene(
            width: RenderProtocol.viewportWidth,
            height: RenderProtocol.viewportHeight,
            sideRoads: rankedRoads,
            traveledRoute: traveledPoints.count >= 2 ? [ScreenPolyline(points: traveledPoints)] : [],
            upcomingRoute: upcomingPoints.count >= 2 ? [ScreenPolyline(points: upcomingPoints)] : [],
            marker: anchorMarker,
            maneuverPoint: maneuverPoint,
            maneuver: instruction?.maneuver ?? .straight,
            distanceMeters: Int((instruction?.distanceMeters ?? 0).rounded()),
            streetName: instruction?.streetName ?? ""
        )
    }

    public static func marker(route: RoutePlan, anchorProgressIndex: Int, location: GeoPoint) -> ScreenPoint? {
        guard route.points.count >= 2, route.points.indices.contains(anchorProgressIndex), location.isValid else { return nil }
        let endIndex = forwardEnd(route.points, from: anchorProgressIndex, maximumMeters: 600)
        let startIndex = backwardStart(route.points, from: anchorProgressIndex, maximumMeters: 30)
        let visible = Array(route.points[startIndex...endIndex])
        guard visible.count >= 2 else { return nil }
        let transform = Transform(
            origin: route.points[anchorProgressIndex],
            headingTarget: route.points[min(anchorProgressIndex + 1, route.points.count - 1)],
            points: visible
        )
        let point = transform.projectUnclamped(location)
        return (0..<RenderProtocol.viewportWidth).contains(point.x) && (0..<RenderProtocol.viewportHeight).contains(point.y)
            ? point : nil
    }

    private static func forwardEnd(_ points: [GeoPoint], from index: Int, maximumMeters: Double) -> Int {
        var total = 0.0, result = index
        while result + 1 < points.count {
            let distance = meters(points[result], points[result + 1])
            if total + distance > maximumMeters, result > index { break }
            total += distance; result += 1
        }
        return result
    }

    private static func backwardStart(_ points: [GeoPoint], from index: Int, maximumMeters: Double) -> Int {
        var total = 0.0, result = index
        while result > 0 {
            let distance = meters(points[result - 1], points[result])
            if total + distance > maximumMeters { break }
            total += distance; result -= 1
        }
        return result
    }

    private static func meters(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let latitude = (a.latitude + b.latitude) / 2 * .pi / 180
        return hypot((b.longitude - a.longitude) * 111_320 * cos(latitude), (b.latitude - a.latitude) * 111_132)
    }

    private static func pointSegmentDistance(_ point: ScreenPoint, _ start: ScreenPoint, _ end: ScreenPoint) -> Double {
        let dx = Double(end.x - start.x), dy = Double(end.y - start.y)
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(Double(point.x - start.x), Double(point.y - start.y)) }
        let projection = max(0, min(1, (Double(point.x - start.x) * dx + Double(point.y - start.y) * dy) / lengthSquared))
        return hypot(Double(point.x) - (Double(start.x) + projection * dx), Double(point.y) - (Double(start.y) + projection * dy))
    }

    private static func simplify(_ points: [ScreenPoint], tolerance: Int) -> [ScreenPoint] {
        guard tolerance > 0, points.count > 2 else { return points }
        let threshold = tolerance * tolerance
        var result = [points[0]]
        for point in points.dropFirst().dropLast() {
            let previous = result[result.count - 1]
            let dx = point.x - previous.x
            let dy = point.y - previous.y
            if dx * dx + dy * dy >= threshold { result.append(point) }
        }
        result.append(points[points.count - 1])
        return result.count >= 2 ? result : points
    }

    private struct Transform {
        let origin: GeoPoint
        let sine: Double
        let cosine: Double
        let scale: Double

        init(origin: GeoPoint, headingTarget: GeoPoint, points: [GeoPoint]) {
            self.origin = origin
            let vector = Self.meters(point: headingTarget, origin: origin)
            let heading = atan2(vector.x, vector.y)
            let localSine = sin(heading)
            let localCosine = cos(heading)
            sine = localSine
            cosine = localCosine
            let rotated = points.map { point -> (x: Double, y: Double) in
                let meters = Self.meters(point: point, origin: origin)
                return (
                    meters.x * localCosine - meters.y * localSine,
                    meters.x * localSine + meters.y * localCosine
                )
            }
            let maxX = max(1, rotated.map { abs($0.x) }.max() ?? 1)
            let maxForward = max(1, rotated.map(\.y).max() ?? 1)
            scale = min(88 / maxX, 296 / maxForward)
        }

        func project(_ point: GeoPoint) -> ScreenPoint {
            let value = projectUnclamped(point)
            return ScreenPoint(x: min(211, max(0, value.x)), y: min(359, max(0, value.y)))
        }

        func projectUnclamped(_ point: GeoPoint) -> ScreenPoint {
            let meters = Self.meters(point: point, origin: origin)
            let right = meters.x * cosine - meters.y * sine
            let forward = meters.x * sine + meters.y * cosine
            return ScreenPoint(x: Int((106 + right * scale).rounded()), y: Int((320 - forward * scale).rounded()))
        }

        private static func meters(point: GeoPoint, origin: GeoPoint) -> (x: Double, y: Double) {
            let latitude = (point.latitude + origin.latitude) / 2 * .pi / 180
            return ((point.longitude - origin.longitude) * 111_320 * cos(latitude), (point.latitude - origin.latitude) * 111_132)
        }
    }
}
