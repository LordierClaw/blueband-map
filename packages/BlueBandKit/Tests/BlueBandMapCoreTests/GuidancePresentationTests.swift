import XCTest
@testable import BlueBandMapCore

final class GuidancePresentationTests: XCTestCase {
    private let route = RoutePlan(
        points: [
            GeoPoint(latitude: 10, longitude: 106),
            GeoPoint(latitude: 10.000_018, longitude: 106),
            GeoPoint(latitude: 10.001, longitude: 106),
            GeoPoint(latitude: 10.001, longitude: 106.001),
        ],
        instructions: [
            RouteInstruction(distanceMeters: 2, headingDegrees: 0, sign: 0, interval: 0...1, streetName: "Short"),
            RouteInstruction(distanceMeters: 109, headingDegrees: 90, sign: 2, interval: 1...2, streetName: "Turn Road"),
            RouteInstruction(distanceMeters: 109, headingDegrees: 90, sign: 0, interval: 2...3, streetName: "After"),
        ],
        distanceMeters: 220
    )

    func testShowsNextTurnUntilMatchedGeometryPassesItsBoundary() throws {
        let progress = RouteProgress(
            pointIndex: 0, matchedSegmentIndex: 0, matchedFraction: 0,
            distanceFromRouteMeters: 0, matchedLocation: route.points[0],
            shouldReroute: false, status: .navigating
        )

        let selected = try XCTUnwrap(GuidancePresentationPolicy.select(
            route: route, progress: progress, horizontalAccuracyMeters: 10
        ))

        XCTAssertEqual(selected.instructionIndex, 1)
        XCTAssertEqual(selected.instruction.maneuver, .right)
        XCTAssertEqual(selected.maneuverPointIndex, 1)
        XCTAssertEqual(selected.distanceMeters, 2, accuracy: 0.2)
    }

    func testDoesNotSkipInstructionOutsidePassRadius() throws {
        let progress = RouteProgress(
            pointIndex: 1, matchedSegmentIndex: 1, matchedFraction: 0,
            distanceFromRouteMeters: 0, matchedLocation: route.points[1],
            shouldReroute: false, status: .navigating
        )

        let selected = try XCTUnwrap(GuidancePresentationPolicy.select(
            route: route, progress: progress, horizontalAccuracyMeters: 25
        ))

        XCTAssertEqual(selected.instructionIndex, 2)
        XCTAssertEqual(selected.instruction.maneuver, .straight)
        XCTAssertEqual(selected.maneuverPointIndex, 2)
    }

    func testUsesProviderDistancesWhenInstructionIntervalsOverlap() throws {
        let route = RoutePlan(
            points: [
                GeoPoint(latitude: 0, longitude: 0),
                GeoPoint(latitude: 0, longitude: 0.001),
                GeoPoint(latitude: 0, longitude: 0.002),
                GeoPoint(latitude: 0, longitude: 0.003),
            ],
            instructions: [
                RouteInstruction(distanceMeters: 37, headingDegrees: 0, sign: 0, interval: 0...0, streetName: ""),
                RouteInstruction(distanceMeters: 109, headingDegrees: 90, sign: 2, interval: 0...1, streetName: "Yên Bình"),
                RouteInstruction(distanceMeters: 11, headingDegrees: 0, sign: -2, interval: 1...1, streetName: "Yên Phúc"),
                RouteInstruction(distanceMeters: 72, headingDegrees: 90, sign: 2, interval: 1...1, streetName: "Đường TT18"),
                RouteInstruction(distanceMeters: 62, headingDegrees: 0, sign: -2, interval: 1...2, streetName: "Bạch Thái Bưởi"),
                RouteInstruction(distanceMeters: 42, headingDegrees: 0, sign: 0, interval: 2...3, streetName: "Đích"),
                RouteInstruction(distanceMeters: 0, headingDegrees: 0, sign: 4, interval: 3...3, streetName: ""),
            ],
            distanceMeters: 333
        )
        let start = RouteProgress(
            pointIndex: 0, matchedSegmentIndex: 0, matchedFraction: 0,
            distanceFromRouteMeters: 0, matchedLocation: route.points[0],
            shouldReroute: false, status: .navigating
        )

        let first = try XCTUnwrap(GuidancePresentationPolicy.select(
            route: route, progress: start, horizontalAccuracyMeters: 5
        ))

        XCTAssertEqual(first.instructionIndex, 1)
        XCTAssertEqual(first.instruction.maneuver, .right)
        XCTAssertEqual(first.instruction.streetName, "Yên Bình")
        XCTAssertEqual(first.distanceMeters, 37, accuracy: 0.1)

        let afterFirstStep = RouteProgress(
            pointIndex: 0, matchedSegmentIndex: 0, matchedFraction: 0.4,
            distanceFromRouteMeters: 0,
            matchedLocation: GeoPoint(latitude: 0, longitude: 0.0004),
            shouldReroute: false, status: .navigating
        )
        let second = try XCTUnwrap(GuidancePresentationPolicy.select(
            route: route, progress: afterFirstStep, horizontalAccuracyMeters: 5
        ))

        XCTAssertEqual(second.instructionIndex, 2)
        XCTAssertEqual(second.instruction.maneuver, .left)
        XCTAssertEqual(second.instruction.streetName, "Yên Phúc")
        XCTAssertGreaterThan(second.distanceMeters, 100)
        XCTAssertLessThan(second.distanceMeters, 103)
    }

    func testStationaryBearingFollowsMatchedRouteTangent() throws {
        let progress = RouteProgress(
            pointIndex: 2, matchedSegmentIndex: 2, matchedFraction: 0.25,
            distanceFromRouteMeters: 0, matchedLocation: route.points[2],
            shouldReroute: false, status: .navigating
        )

        XCTAssertEqual(GuidancePresentationPolicy.routeBearing(route: route, progress: progress), 90, accuracy: 0.5)
    }

    func testStationaryBearingUsesImmediateTangentBeforeLaterBend() {
        let origin = GeoPoint(latitude: 10, longitude: 106)
        let north = GeoPoint(latitude: 10.001, longitude: 106)
        let eastAfterBend = GeoPoint(latitude: 10.001, longitude: 106.001)
        let route = RoutePlan(
            points: [origin, north, eastAfterBend],
            instructions: [RouteInstruction(
                distanceMeters: 220, headingDegrees: 90, sign: 2,
                interval: 0...2, streetName: "After Bend"
            )],
            distanceMeters: 220
        )
        let progress = RouteProgress(
            pointIndex: 0, matchedSegmentIndex: 0, matchedFraction: 0,
            distanceFromRouteMeters: 0, matchedLocation: origin,
            shouldReroute: false, status: .navigating
        )
        let selection = GuidanceSelection(
            instructionIndex: 0,
            instruction: route.instructions[0],
            maneuverPointIndex: 2,
            distanceMeters: 220
        )

        XCTAssertEqual(
            GuidancePresentationPolicy.stationaryBearing(
                route: route, progress: progress, selection: selection
            ),
            0,
            accuracy: 0.5
        )
    }

    func testStationaryBearingSkipsDegenerateForwardPoint() throws {
        let origin = GeoPoint(latitude: 10, longitude: 106)
        let east = GeoPoint(latitude: 10, longitude: 106.001)
        let route = RoutePlan(
            points: [origin, origin, east],
            instructions: [
                RouteInstruction(distanceMeters: 0, headingDegrees: 0, sign: 0, interval: 0...1, streetName: "Duplicate"),
                RouteInstruction(distanceMeters: 100, headingDegrees: 90, sign: 0, interval: 1...2, streetName: "East")
            ],
            distanceMeters: 100
        )
        let progress = RouteProgress(
            pointIndex: 0, matchedSegmentIndex: 0, matchedFraction: 0,
            distanceFromRouteMeters: 0, matchedLocation: origin,
            shouldReroute: false, status: .navigating
        )
        let degenerate = GuidanceSelection(
            instructionIndex: 0,
            instruction: route.instructions[0],
            maneuverPointIndex: 1,
            distanceMeters: 0
        )

        XCTAssertEqual(
            GuidancePresentationPolicy.forwardPoint(route: route, progress: progress, selection: degenerate),
            east
        )
        XCTAssertEqual(
            GuidancePresentationPolicy.stationaryBearing(route: route, progress: progress, selection: degenerate),
            90,
            accuracy: 0.5
        )
    }

    func testCourseActivatesAfterTwoEligibleFixesAndFallsBackAfterThree() {
        var policy = GuidanceBearingPolicy()
        let first = policy.update(horizontalAccuracyMeters: 5, speedMetersPerSecond: 2, courseDegrees: 92, routeBearingDegrees: 0, confirmedBearingDegrees: 0, secondsSinceRefresh: 20)
        let second = policy.update(horizontalAccuracyMeters: 5, speedMetersPerSecond: 2, courseDegrees: 92, routeBearingDegrees: 0, confirmedBearingDegrees: 0, secondsSinceRefresh: 20)
        XCTAssertEqual(first.source, .route)
        XCTAssertEqual(second.source, .course)
        XCTAssertTrue(second.shouldRefresh)

        for index in 0..<2 {
            let held = policy.update(horizontalAccuracyMeters: 30, speedMetersPerSecond: -1, courseDegrees: -1, routeBearingDegrees: 0, confirmedBearingDegrees: 92, secondsSinceRefresh: 20)
            XCTAssertEqual(held.source, .course, "invalid fix \(index) must not oscillate the camera")
        }
        let fallback = policy.update(horizontalAccuracyMeters: 30, speedMetersPerSecond: -1, courseDegrees: -1, routeBearingDegrees: 0, confirmedBearingDegrees: 92, secondsSinceRefresh: 20)
        XCTAssertEqual(fallback.source, .route)
    }

    func testRefreshThresholdUsesCircularDifferenceAndTwelveSeconds() {
        XCTAssertEqual(GuidanceBearingPolicy.angularDifference(350, 10), 20, accuracy: 0.001)
        XCTAssertFalse(GuidanceBearingPolicy.shouldRefresh(preferred: 30, confirmed: 0, secondsSinceRefresh: 11.9))
        XCTAssertTrue(GuidanceBearingPolicy.shouldRefresh(preferred: 30, confirmed: 0, secondsSinceRefresh: 12))
        XCTAssertFalse(GuidanceBearingPolicy.shouldRefresh(preferred: 29, confirmed: 0, secondsSinceRefresh: 20))
    }

    func testOverlayGeometrySplitsExactlyAtFractionalMatch() throws {
        let matched = GeoPoint(latitude: 10.000_009, longitude: 106)
        let progress = RouteProgress(
            pointIndex: 0, matchedSegmentIndex: 0, matchedFraction: 0.5,
            distanceFromRouteMeters: 0, matchedLocation: matched,
            shouldReroute: false, status: .navigating
        )
        let selection = try XCTUnwrap(GuidancePresentationPolicy.select(
            route: route, progress: progress, horizontalAccuracyMeters: 5
        ))

        let geometry = RouteOverlayGeometry.make(route: route, progress: progress, selection: selection)

        XCTAssertEqual(geometry.traveled.last, matched)
        XCTAssertEqual(geometry.active.first, matched)
        XCTAssertEqual(geometry.active.last, route.points.last)
        XCTAssertTrue(geometry.context.isEmpty)
    }

    func testOffRouteMarkerUsesRawAcceptedLocation() {
        let raw = GeoPoint(latitude: 10.002, longitude: 106.002)
        let snapped = route.points[1]
        let progress = RouteProgress(
            pointIndex: 1, matchedSegmentIndex: 1, matchedFraction: 0,
            distanceFromRouteMeters: 50, matchedLocation: snapped,
            shouldReroute: true, status: .navigating
        )

        XCTAssertEqual(GuidancePresentationPolicy.markerLocation(progress: progress, rawLocation: raw), raw)
    }
}
