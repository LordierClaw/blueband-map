import XCTest
@testable import BlueBandMapCore

final class VietmapRouteTests: XCTestCase {
    func testFrozenPlaybackShapeSurvivesParserThroughPreviewAndLiveUpdate() throws {
        // Same E5 deltas translated to (0,0): a literal, non-secret independent replay vector.
        let body = Data(#"{"code":"OK","paths":[{"distance":465,"points_encoded":true,"points":"??kGrAcKzBEIIEICK@KBIJCL@NqBnAsFfE","instructions":[{"distance":465,"heading":0,"sign":6,"interval":[0,11],"street_name":"Circle","text":"Tại vòng xoay, rẽ lối rẽ 2 vào đường Circle"}]}]}"#.utf8)
        let route = try VietmapRouteClient.parse(body), instruction = try XCTUnwrap(route.instructions.first)
        XCTAssertEqual(instruction.roundaboutDirection, .straight)
        XCTAssertEqual(instruction.roundaboutExit, 2)
        let preview = try RenderNavigationPreview(maneuver: .roundabout, distanceMeters: 80, street: "Circle",
            x: 106, y: 374, headingBucket: 0, destinationMode: .hidden, destinationX: 0, destinationY: 0,
            roundaboutExit: instruction.roundaboutExit, roundaboutDirection: instruction.roundaboutDirection)
        let live = try NavigationUpdate(scene: "scene-1", seq: 1, x: 106, y: 374, maneuver: .roundabout,
            distanceMeters: 80, street: "Circle", status: .navigating,
            roundaboutExit: instruction.roundaboutExit, roundaboutDirection: instruction.roundaboutDirection)
        XCTAssertEqual(preview.jsonBody()["roundaboutDirection"], .string("straight"))
        XCTAssertEqual(live.jsonBody()["roundaboutDirection"], .string("straight"))
    }

    func testFrozenPlaybackRoundaboutIntervalAlreadyIncludesOutlet() {
        // Translated E5 offsets from the user's frozen playback shape; no raw capture or location.
        let offsets = [(0, 0), (134, -42), (328, -104), (331, -99), (336, -96),
                       (341, -94), (347, -95), (353, -97), (358, -103), (360, -110),
                       (359, -118), (416, -158), (538, -258)]
        let points = offsets.map { GeoPoint(latitude: 20 + Double($0.0) / 100_000,
                                            longitude: 105 + Double($0.1) / 100_000) }
        for end in [10, 11, 12] {
            let route = RoutePlan(points: points, instructions: [
                RouteInstruction(distanceMeters: 465, headingDegrees: 0, sign: 6,
                                 interval: 0...end, streetName: "Circle", roundaboutExit: 2)
            ], distanceMeters: 465)
            XCTAssertEqual(route.instructions[0].roundaboutDirection, .straight, "interval end=\(end)")
        }
    }

    func testRoundaboutGeometrySelectsRelativeExitNotLocalExitTurnOrExitNumber() {
        for (sweep, expected) in [(90, "right"), (180, "straight"), (270, "left"), (360, "uTurn")] {
            for rotation in [0.0, 73, 181, 350] {
                let route = circularRoute(sweep: sweep, rotation: rotation)
                let debug = NavigationDebugFormatter.export(state: "navigating", start: nil, destination: nil,
                    routeDistanceMeters: route.distanceMeters, alternativePathCount: 1,
                    instructions: route.instructions, entries: [])
                XCTAssertTrue(debug.contains("roundaboutDirection=\(expected)"), "sweep=\(sweep), rotation=\(rotation): \(debug)")
                XCTAssertEqual(RoundaboutGeometry.direction(points: route.points,
                    interval: 0...(route.points.count - 1))?.rawValue, expected,
                    "same circle with outlet inside instruction: sweep=\(sweep), rotation=\(rotation)")
            }
        }
    }

    private func circularRoute(sweep: Int, rotation: Double) -> RoutePlan {
        // Independent circle fixture: approach north; CCW circulation; radial outlet.
        // All cases deliberately carry exit=2 and local exit sign=2.
        var xy: [(Double, Double)] = [(0, -120), (0, -20)]
        for angle in stride(from: -75, through: -90 + sweep, by: 15) {
            let radians = Double(angle) * .pi / 180
            xy.append((20 * cos(radians), 20 * sin(radians)))
        }
        let end = Double(-90 + sweep) * .pi / 180
        xy.append((80 * cos(end), 80 * sin(end)))
        let rotation = rotation * .pi / 180
        let points = xy.map { x, y in
            GeoPoint(latitude: 20 + (y * cos(rotation) - x * sin(rotation)) / 111_195,
                     longitude: 105 + (x * cos(rotation) + y * sin(rotation)) / (111_195 * cos(20 * .pi / 180)))
        }
        return RoutePlan(points: points, instructions: [
            RouteInstruction(distanceMeters: 200, headingDegrees: 0, sign: 6,
                             interval: 0...(points.count - 2), streetName: "Circle", roundaboutExit: 2),
            RouteInstruction(distanceMeters: 60, headingDegrees: 0, sign: 2,
                             interval: (points.count - 2)...(points.count - 1), streetName: "Exit")
        ], distanceMeters: 260)
    }

    func testRoundaboutGeometryRejectsMissingOutletStraightAndClockwisePaths() {
        let circle = circularRoute(sweep: 180, rotation: 0)
        let last = circle.points.count - 1
        XCTAssertNil(RoundaboutGeometry.direction(points: Array(circle.points.dropLast()), interval: 0...(last - 1)))
        let straight = (0..<10).map { GeoPoint(latitude: 20 + Double($0) * 0.0001, longitude: 105) }
        XCTAssertNil(RoundaboutGeometry.direction(points: straight, interval: 0...8))
        let mirrored = circle.points.map { GeoPoint(latitude: $0.latitude, longitude: 210 - $0.longitude) }
        XCTAssertNil(RoundaboutGeometry.direction(points: mirrored, interval: 0...(last - 1)))
        var invalid = circle.points
        invalid[4] = GeoPoint(latitude: .nan, longitude: 105)
        XCTAssertNil(RoundaboutGeometry.direction(points: invalid, interval: 0...(last - 1)))
        var duplicated = circle.points
        duplicated.insert(circle.points[4], at: 4)
        XCTAssertEqual(RoundaboutGeometry.direction(points: duplicated, interval: 0...last), .straight)
    }

    func testNguyenKhuyenShapeUsesApproachBeforeArcAndOutletAfterArc() {
        // Independently reconstructed headings/lengths, not a raw provider capture.
        let segments: [(Double, Double)] = [(344, 31), (344, 155), (343, 225),
            (52, 6), (33, 6), (15, 6), (358, 6), (339, 7), (315, 8), (289, 8), (261, 8), (326, 76)]
        var points = [GeoPoint(latitude: 20, longitude: 105)]
        for (heading, meters) in segments {
            let previous = points.last!, angle = heading * .pi / 180
            points.append(GeoPoint(latitude: previous.latitude + meters * cos(angle) / 111_195,
                longitude: previous.longitude + meters * sin(angle) / (111_195 * cos(20 * .pi / 180))))
        }
        XCTAssertEqual(RoundaboutGeometry.direction(points: points, interval: 0...(points.count - 2)), .straight)
    }

    func testProviderRoundaboutExitSurvivesIntoDebugGuidance() throws {
        let body = Data(#"{"code":"OK","paths":[{"distance":465,"points_encoded":true,"points":"????","instructions":[{"distance":465,"heading":0,"sign":6,"interval":[0,1],"street_name":"Nguyễn Khuyến","text":"Tại vòng xoay, rẽ lối rẽ 2 vào đường Nguyễn Khuyến"}]}]}"#.utf8)
        let route = try VietmapRouteClient.parse(body)
        let debug = NavigationDebugFormatter.export(state: "navigating", start: nil, destination: nil,
            routeDistanceMeters: route.distanceMeters, alternativePathCount: 1,
            instructions: route.instructions, entries: [])
        XCTAssertTrue(debug.contains("roundaboutExit=2"), "retain the actual exit; a roundabout sign alone does not mean turn right")
        XCTAssertEqual(route.instructions[0].streetName, "Nguyễn Khuyến")
    }

    func testDecodesGooglePolylineFive() throws {
        XCTAssertEqual(try GooglePolyline5.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@"), [
            GeoPoint(latitude: 38.5, longitude: -120.2),
            GeoPoint(latitude: 40.7, longitude: -120.95),
            GeoPoint(latitude: 43.252, longitude: -126.453),
        ])
    }

    func testParsesBoundedRouteV4ResponseAndManeuvers() throws {
        let body = Data(#"{"code":"OK","paths":[{"distance":2532.6,"points_encoded":true,"points":"??gE?gEgE","instructions":[{"distance":120,"heading":0,"sign":0,"interval":[0,1],"street_name":"Đường A"},{"distance":40,"heading":90,"sign":2,"interval":[1,2],"street_name":"  Đường B\n"},{"distance":0,"heading":0,"sign":4,"interval":[2,2],"street_name":""}]}]}"#.utf8)

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
        XCTAssertEqual(poor.matchedLocation, good.matchedLocation)
        XCTAssertEqual(poor.status, .gpsLow)
    }

    func testConsecutiveFixesStayOnTheCurrentSegmentPastItsMidpoint() throws {
        let route = RoutePlan(
            points: [
                GeoPoint(latitude: 10, longitude: 106),
                GeoPoint(latitude: 10.001, longitude: 106),
                GeoPoint(latitude: 10.002, longitude: 106),
            ],
            instructions: [],
            distanceMeters: 222
        )
        var tracker = RouteProgressTracker()

        _ = tracker.update(route: route, location: GeoPoint(latitude: 10.0006, longitude: 106), horizontalAccuracyMeters: 5)
        let next = tracker.update(route: route, location: GeoPoint(latitude: 10.0007, longitude: 106), horizontalAccuracyMeters: 5)

        XCTAssertEqual(next.matchedSegmentIndex, 0)
        XCTAssertEqual(next.matchedFraction, 0.7, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(next.matchedLocation).latitude, 10.0007, accuracy: 0.000001)
    }
}
