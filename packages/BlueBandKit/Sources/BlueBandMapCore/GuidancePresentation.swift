import Foundation

public struct GuidanceSelection: Equatable, Sendable {
    public let instructionIndex: Int
    public let instruction: RouteInstruction
    public let distanceMeters: Double
}

public enum GuidancePresentationPolicy {
    public static func select(
        route: RoutePlan,
        progress: RouteProgress,
        horizontalAccuracyMeters: Double
    ) -> GuidanceSelection? {
        guard !route.instructions.isEmpty, route.points.count >= 2 else { return nil }
        var index = route.instructions.firstIndex {
            $0.interval.upperBound >= progress.matchedSegmentIndex
        } ?? route.instructions.count - 1
        let passRadius = max(8, min(20, horizontalAccuracyMeters.isFinite ? horizontalAccuracyMeters : 8))
        var remaining = distance(to: route.instructions[index], route: route, progress: progress)
        while remaining <= passRadius, index + 1 < route.instructions.count {
            index += 1
            remaining = distance(to: route.instructions[index], route: route, progress: progress)
        }
        return GuidanceSelection(
            instructionIndex: index,
            instruction: route.instructions[index],
            distanceMeters: remaining
        )
    }

    public static func routeBearing(route: RoutePlan, progress: RouteProgress) -> Double {
        guard route.points.count >= 2 else { return 0 }
        let startIndex = min(progress.matchedSegmentIndex, route.points.count - 2)
        let origin = progress.matchedLocation ?? route.points[startIndex]
        for index in (startIndex + 1)..<route.points.count {
            if meters(origin, route.points[index]) > 0.5 {
                return bearing(origin, route.points[index])
            }
        }
        return 0
    }

    private static func distance(to instruction: RouteInstruction, route: RoutePlan, progress: RouteProgress) -> Double {
        let target = min(instruction.interval.upperBound, route.points.count - 1)
        let segment = min(progress.matchedSegmentIndex, route.points.count - 2)
        guard target > segment else { return 0 }
        let matched = progress.matchedLocation ?? route.points[segment]
        var result = meters(matched, route.points[segment + 1])
        if segment + 1 < target {
            for index in (segment + 1)..<target { result += meters(route.points[index], route.points[index + 1]) }
        }
        return result
    }

    private static func bearing(_ from: GeoPoint, _ to: GeoPoint) -> Double {
        let radians = Double.pi / 180
        let latitude1 = from.latitude * radians, latitude2 = to.latitude * radians
        let longitude = (to.longitude - from.longitude) * radians
        let y = sin(longitude) * cos(latitude2)
        let x = cos(latitude1) * sin(latitude2) - sin(latitude1) * cos(latitude2) * cos(longitude)
        let degrees = atan2(y, x) / radians
        return degrees < 0 ? degrees + 360 : degrees
    }

    private static func meters(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let latitude = (a.latitude + b.latitude) / 2 * .pi / 180
        return hypot((b.longitude - a.longitude) * 111_320 * cos(latitude), (b.latitude - a.latitude) * 111_132)
    }
}

public enum GuidanceBearingSource: String, Equatable, Sendable { case route, course }

public struct GuidanceBearingDecision: Equatable, Sendable {
    public let bearingDegrees: Double
    public let source: GuidanceBearingSource
    public let deltaDegrees: Double
    public let shouldRefresh: Bool
}

public struct GuidanceBearingPolicy: Sendable {
    private var eligibleFixes = 0
    private var ineligibleFixes = 0
    private var usesCourse = false
    private var lastCourse = 0.0

    public init() {}

    public mutating func update(
        horizontalAccuracyMeters: Double,
        speedMetersPerSecond: Double,
        courseDegrees: Double,
        routeBearingDegrees: Double,
        confirmedBearingDegrees: Double,
        secondsSinceRefresh: Double
    ) -> GuidanceBearingDecision {
        let eligible = horizontalAccuracyMeters.isFinite && horizontalAccuracyMeters >= 0 && horizontalAccuracyMeters <= 25 &&
            speedMetersPerSecond.isFinite && speedMetersPerSecond >= 1 &&
            courseDegrees.isFinite && (0...360).contains(courseDegrees)
        if eligible {
            eligibleFixes += 1
            ineligibleFixes = 0
            lastCourse = courseDegrees
            if eligibleFixes >= 2 { usesCourse = true }
        } else {
            eligibleFixes = 0
            ineligibleFixes += 1
            if ineligibleFixes >= 3 { usesCourse = false }
        }
        let preferred = usesCourse ? lastCourse : routeBearingDegrees
        return GuidanceBearingDecision(
            bearingDegrees: preferred,
            source: usesCourse ? .course : .route,
            deltaDegrees: Self.angularDifference(preferred, confirmedBearingDegrees),
            shouldRefresh: Self.shouldRefresh(
                preferred: preferred,
                confirmed: confirmedBearingDegrees,
                secondsSinceRefresh: secondsSinceRefresh
            )
        )
    }

    public static func angularDifference(_ first: Double, _ second: Double) -> Double {
        let difference = abs(first - second).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    public static func shouldRefresh(preferred: Double, confirmed: Double, secondsSinceRefresh: Double) -> Bool {
        angularDifference(preferred, confirmed) >= 30 && secondsSinceRefresh >= 12
    }
}
