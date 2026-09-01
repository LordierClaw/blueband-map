import XCTest
@testable import BlueBandMapCore

final class VietmapRouteTests: XCTestCase {
    func testDecodesGooglePolylineFive() throws {
        XCTAssertEqual(try GooglePolyline5.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@"), [
            GeoPoint(latitude: 38.5, longitude: -120.2),
            GeoPoint(latitude: 40.7, longitude: -120.95),
            GeoPoint(latitude: 43.252, longitude: -126.453),
        ])
    }

    func testParsesBoundedRouteV4ResponseAndManeuvers() throws {
        let body = Data(#"{"code":"OK","paths":[{"distance":2532.6,"points_encoded":true,"points":"??gE?gEgE","instructions":[{"distance":120,"heading":0,"sign":0,"interval":[0,1],"street_name":"Đường A"},{"distance":40,"heading":90,"sign":2,"interval":[1,2],"street_name":"Đường B"},{"distance":0,"heading":0,"sign":4,"interval":[2,2],"street_name":""}]}]}"#.utf8)

        let route = try VietmapRouteClient.parse(body)

        XCTAssertEqual(route.points.count, 3)
        XCTAssertEqual(route.instructions.map(\.maneuver), [.straight, .right, .arrive])
        XCTAssertEqual(route.instructions[1].streetName, "Đường B")
    }

    func testSelectsShortestValidPathWhenProviderReturnsAlternatives() throws {
        let body = Data(#"{"code":"OK","paths":[{"distance":20,"points_encoded":true,"points":"??gE?gEgE","instructions":[{"distance":20,"heading":0,"sign":0,"interval":[0,2],"street_name":"Long"}]},{"distance":10,"points_encoded":true,"points":"??gE?gEgE","instructions":[{"distance":10,"heading":90,"sign":2,"interval":[0,2],"street_name":"Short"}]}]}"#.utf8)

        let route = try VietmapRouteClient.parse(body)

        XCTAssertEqual(route.distanceMeters, 10)
        XCTAssertEqual(route.alternativePathCount, 2)
        XCTAssertEqual(route.instructions.first?.streetName, "Short")
        XCTAssertEqual(route.instructions.first?.maneuver, .right)
    }

    func testRejectsInvalidIntervalsAndSelectsShortestOfMultiplePaths() throws {
        let invalidInterval = Data(#"{"code":"OK","paths":[{"distance":1,"points_encoded":true,"points":"????","instructions":[{"distance":1,"heading":0,"sign":0,"interval":[0,9],"street_name":""}]}]}"#.utf8)
        let multiplePaths = Data(#"{"code":"OK","paths":[{"distance":1,"points_encoded":true,"points":"????","instructions":[]},{"distance":1,"points_encoded":true,"points":"????","instructions":[]}]}"#.utf8)

        XCTAssertThrowsError(try VietmapRouteClient.parse(invalidInterval))
        XCTAssertEqual(try VietmapRouteClient.parse(multiplePaths).distanceMeters, 1)
    }

    func testBuildsBoundedMotorcycleRequestWithoutAnnotations() throws {
        let request = try VietmapRouteClient.request(
            origin: GeoPoint(latitude: 10.759157, longitude: 106.675859),
            destination: GeoPoint(latitude: 10.762622, longitude: 106.660172),
            serviceKey: "secret",
            headingDegrees: 45
        )

        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.maximumResponseBytes, 256 * 1_024)
        let query = try XCTUnwrap(URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.filter { $0.name == "vehicle" }.first?.value, "motorcycle")
        XCTAssertEqual(query.filter { $0.name == "points_encoded" }.first?.value, "true")
        XCTAssertFalse(query.contains { $0.name == "annotations" })
    }

    func testProgressIsMonotonicAndRequestsRerouteAfterThreeGoodOffRouteFixes() throws {
        let route = RoutePlan(
            points: [
                GeoPoint(latitude: 10, longitude: 106),
                GeoPoint(latitude: 10.001, longitude: 106),
                GeoPoint(latitude: 10.002, longitude: 106),
            ],
            instructions: [RouteInstruction(distanceMeters: 200, headingDegrees: 0, sign: 0, interval: 0...2, streetName: "Road")],
            distanceMeters: 222
        )
        var tracker = RouteProgressTracker()
        let onRoute = tracker.update(route: route, location: GeoPoint(latitude: 10.0015, longitude: 106), horizontalAccuracyMeters: 5)
        XCTAssertGreaterThanOrEqual(onRoute.pointIndex, 1)
        XCTAssertEqual(onRoute.matchedSegmentIndex, 1)
        XCTAssertEqual(onRoute.matchedFraction, 0.5, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(onRoute.matchedLocation).longitude, 106, accuracy: 0.000001)

        for _ in 0..<2 {
            XCTAssertFalse(tracker.update(route: route, location: GeoPoint(latitude: 10.0015, longitude: 106.001), horizontalAccuracyMeters: 5).shouldReroute)
        }
        XCTAssertTrue(tracker.update(route: route, location: GeoPoint(latitude: 10.0015, longitude: 106.001), horizontalAccuracyMeters: 5).shouldReroute)

        let older = tracker.update(route: route, location: GeoPoint(latitude: 10.0001, longitude: 106), horizontalAccuracyMeters: 5)
        XCTAssertGreaterThanOrEqual(older.pointIndex, onRoute.pointIndex)
    }

    func testPoorAccuracyKeepsLastProgressAndReportsGPSLow() {
        let route = RoutePlan(
            points: [GeoPoint(latitude: 10, longitude: 106), GeoPoint(latitude: 10.001, longitude: 106)],
            instructions: [],
            distanceMeters: 111
        )
        var tracker = RouteProgressTracker()
        let good = tracker.update(route: route, location: route.points[0], horizontalAccuracyMeters: 5)
        let poor = tracker.update(route: route, location: route.points[1], horizontalAccuracyMeters: 30)
        XCTAssertEqual(poor.pointIndex, good.pointIndex)
        XCTAssertEqual(poor.status, .gpsLow)
    }
}
