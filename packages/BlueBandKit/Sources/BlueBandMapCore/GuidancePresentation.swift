import Foundation

public struct GuidanceSelection: Equatable, Sendable {
    public let instructionIndex: Int
    public let instruction: RouteInstruction
    public let distanceMeters: Double
}

public struct RouteOverlayGeometry: Equatable, Sendable {
    public let subdued: [GeoPoint]
    public let traveled: [GeoPoint]
    public let active: [GeoPoint]
    public let context: [GeoPoint]

    public init(subdued: [GeoPoint], traveled: [GeoPoint], active: [GeoPoint], context: [GeoPoint]) {
        self.subdued = subdued
        self.traveled = traveled
        self.active = active
        self.context = context
    }

    public static func make(
        route: RoutePlan,
        progress: RouteProgress,
        selection: GuidanceSelection
    ) -> Self {
        let segment = min(progress.matchedSegmentIndex, route.points.count - 2)
        let matched = progress.matchedLocation ?? route.points[segment]
        let maneuver = min(selection.instruction.interval.upperBound, route.points.count - 1)
        let traveled = Array(route.points.prefix(segment + 1)) + [matched]
        let active = [matched] + (maneuver > segment ? Array(route.points[(segment + 1)...maneuver]) : [])
        var context = [route.points[maneuver]]
        var distance = 0.0
        var index = maneuver
        while index + 1 < route.points.count, context.count == 1 || distance < 80 {
            distance += meters(route.points[index], route.points[index + 1])
            index += 1
            context.append(route.points[index])
        }
        return Self(subdued: route.points, traveled: traveled, active: active, context: context)
    }

    private static func meters(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let latitude = (a.latitude + b.latitude) / 2 * .pi / 180
        return hypot((b.longitude - a.longitude) * 111_320 * cos(latitude), (b.latitude - a.latitude) * 111_132)
    }
}

public enum GuidancePresentationPolicy {
    public static func markerLocation(progress: RouteProgress, rawLocation: GeoPoint) -> GeoPoint {
        progress.shouldReroute ? rawLocation : (progress.matchedLocation ?? rawLocation)
    }

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
        stationaryBearing(route: route, progress: progress, selection: nil)
    }

    public static func forwardPoint(
        route: RoutePlan,
        progress: RouteProgress,
        selection: GuidanceSelection?
    ) -> GeoPoint? {
        guard route.points.count >= 2 else { return nil }
        let startIndex = min(progress.matchedSegmentIndex, route.points.count - 2)
        let origin = progress.matchedLocation ?? route.points[startIndex]
        if let selection {
            let maneuverIndex = min(selection.instruction.interval.upperBound, route.points.count - 1)
            let maneuver = route.points[maneuverIndex]
            if meters(origin, maneuver) > 0.5 { return maneuver }
        }
        return route.points[(startIndex + 1)...].first { meters(origin, $0) > 0.5 }
    }

    public static func stationaryBearing(
        route: RoutePlan,
        progress: RouteProgress,
        selection: GuidanceSelection?
    ) -> Double {
        guard route.points.count >= 2 else { return 0 }
        let startIndex = min(progress.matchedSegmentIndex, route.points.count - 2)
        let origin = progress.matchedLocation ?? route.points[startIndex]
        guard let forward = forwardPoint(route: route, progress: progress, selection: selection) else { return 0 }
        return bearing(origin, forward)
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
