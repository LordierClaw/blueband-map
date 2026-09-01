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

    func testSkipsOnlyGPSIndistinguishableInstruction() throws {
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
        XCTAssertGreaterThan(selected.distanceMeters, 100)
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

        XCTAssertEqual(selected.instructionIndex, 1)
    }

    func testStationaryBearingFollowsMatchedRouteTangent() throws {
        let progress = RouteProgress(
            pointIndex: 2, matchedSegmentIndex: 2, matchedFraction: 0.25,
            distanceFromRouteMeters: 0, matchedLocation: route.points[2],
            shouldReroute: false, status: .navigating
        )

        XCTAssertEqual(GuidancePresentationPolicy.routeBearing(route: route, progress: progress), 90, accuracy: 0.5)
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
}
