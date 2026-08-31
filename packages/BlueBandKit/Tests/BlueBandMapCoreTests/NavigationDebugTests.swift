import XCTest
@testable import BlueBandMapCore

final class NavigationDebugTests: XCTestCase {
    func testExportIncludesRouteStepsAndRedactsExactCoordinates() throws {
        let output = NavigationDebugFormatter.export(
            state: "navigating",
            start: GeoPoint(latitude: 10.123456, longitude: 106.987654),
            destination: GeoPoint(latitude: 10.223456, longitude: 106.887654),
            routeDistanceMeters: 2_428.3,
            alternativePathCount: 2,
            instructions: [
                RouteInstruction(distanceMeters: 120, headingDegrees: 0, sign: 0, interval: 0...2, streetName: "Đường A"),
                RouteInstruction(distanceMeters: 40, headingDegrees: 90, sign: 2, interval: 2...3, streetName: "Đường B"),
            ],
            entries: [
                NavigationDebugEntry(sequence: 1, elapsedMilliseconds: 12, stage: "route.request", detail: "heading=90"),
            ]
        )

        XCTAssertTrue(output.contains("state=navigating"))
        XCTAssertTrue(output.contains("start=10.123,106.988"))
        XCTAssertTrue(output.contains("destination=10.223,106.888"))
        XCTAssertTrue(output.contains("routeDistanceM=2428"))
        XCTAssertTrue(output.contains("alternativePaths=2"))
        XCTAssertTrue(output.contains("step[1] maneuver=straight distanceM=120"))
        XCTAssertTrue(output.contains("step[2] maneuver=right distanceM=40"))
        XCTAssertTrue(output.contains("street=Đường A"))
        XCTAssertTrue(output.contains("street=Đường B"))
        XCTAssertTrue(output.contains("[12ms] #1 route.request heading=90"))
        XCTAssertLessThan(
            try XCTUnwrap(output.range(of: "events:")?.lowerBound),
            try XCTUnwrap(output.range(of: "step[1]")?.lowerBound)
        )
        XCTAssertFalse(output.contains("10.123456"))
        XCTAssertFalse(output.contains("106.987654"))
    }
}
