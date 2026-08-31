import XCTest
@testable import BlueBandMapCore

final class RouteCardSceneTests: XCTestCase {
    func testExtractsWholeRoadPolylinesAndSkipsPaths() {
        let tile = VietmapSceneTile(
            tile: MapboxVectorTile(layers: [
                .init(name: "road", extent: 4_096, features: [
                    .init(geometryType: .lineString, properties: ["class": "primary"], lines: [[
                        .init(x: 0, y: 0), .init(x: 2_048, y: 2_048), .init(x: 4_096, y: 4_096),
                    ]]),
                    .init(geometryType: .lineString, properties: ["class": "path"], lines: [[
                        .init(x: 0, y: 0), .init(x: 4_096, y: 0),
                    ]]),
                ]),
            ]),
            zoom: 1,
            x: 1,
            y: 0
        )

        let roads = VietmapRoadExtractor.extract(tiles: [tile], sourceLayers: ["road"])

        XCTAssertEqual(roads.count, 1)
        XCTAssertEqual(roads[0].points.count, 3)
        XCTAssertTrue(roads[0].isMajor)
        XCTAssertEqual(roads[0].points[0].latitude, 85.0511287798066, accuracy: 1e-12)
        XCTAssertEqual(roads[0].points[0].longitude, 0, accuracy: 1e-12)
        XCTAssertEqual(roads[0].points[2].latitude, 0, accuracy: 1e-12)
        XCTAssertEqual(roads[0].points[2].longitude, 180, accuracy: 1e-12)
    }

    func testBuildsHeadingUpContinuousRouteWithRankedSideRoads() throws {
        let route = RoutePlan(
            points: [
                GeoPoint(latitude: 10.0000, longitude: 106.0000),
                GeoPoint(latitude: 10.0010, longitude: 106.0000),
                GeoPoint(latitude: 10.0020, longitude: 106.0005),
                GeoPoint(latitude: 10.0030, longitude: 106.0010),
            ],
            instructions: [
                RouteInstruction(distanceMeters: 180, headingDegrees: 0, sign: 2, interval: 1...3, streetName: "Next Road")
            ],
            distanceMeters: 400
        )
        let nearby = RoadPolyline(points: [
            GeoPoint(latitude: 10.0018, longitude: 105.9995),
            GeoPoint(latitude: 10.0018, longitude: 106.0007),
        ], isMajor: false)
        let far = RoadPolyline(points: [
            GeoPoint(latitude: 10.0018, longitude: 106.01),
            GeoPoint(latitude: 10.0020, longitude: 106.011),
        ], isMajor: true)

        let scene = try RouteCardBuilder.build(route: route, progressIndex: 1, sideRoads: [far, nearby])

        XCTAssertEqual(scene.width, 212)
        XCTAssertEqual(scene.height, 360)
        XCTAssertEqual(scene.maneuver, .right)
        XCTAssertEqual(scene.streetName, "Next Road")
        XCTAssertEqual(scene.sideRoads.count, 1)
        XCTAssertEqual(scene.marker, ScreenPoint(x: 106, y: 320))
        XCTAssertTrue(scene.upcomingRoute.flatMap(\.points).allSatisfy { (0..<212).contains($0.x) && (0..<360).contains($0.y) })
        XCTAssertLessThan(scene.upcomingRoute.last!.points.last!.y, scene.marker.y)
    }

    func testManeuverPointMarksTheEndOfTheCurrentInstruction() throws {
        let route = RoutePlan(
            points: [
                GeoPoint(latitude: 10.0000, longitude: 106.0000),
                GeoPoint(latitude: 10.0010, longitude: 106.0000),
                GeoPoint(latitude: 10.0020, longitude: 106.0005),
                GeoPoint(latitude: 10.0030, longitude: 106.0010),
            ],
            instructions: [
                RouteInstruction(distanceMeters: 333, headingDegrees: 0, sign: 2, interval: 0...3, streetName: "Next Road")
            ],
            distanceMeters: 400
        )

        let scene = try RouteCardBuilder.build(route: route, progressIndex: 0, sideRoads: [])

        XCTAssertEqual(scene.maneuverPoint, scene.upcomingRoute[0].points.last)
        XCTAssertNotEqual(scene.maneuverPoint, scene.marker)
    }

    func testKeepsAtMostTwelveWholeSideRoadPolylines() throws {
        let route = RoutePlan(
            points: [GeoPoint(latitude: 10, longitude: 106), GeoPoint(latitude: 10.004, longitude: 106)],
            instructions: [],
            distanceMeters: 444
        )
        let roads = (0..<20).map { offset in
            RoadPolyline(points: [
                GeoPoint(latitude: 10.001 + Double(offset) * 0.00001, longitude: 105.9998),
                GeoPoint(latitude: 10.001 + Double(offset) * 0.00001, longitude: 106.0002),
            ], isMajor: offset.isMultiple(of: 2))
        }

        let scene = try RouteCardBuilder.build(route: route, progressIndex: 0, sideRoads: roads)
        XCTAssertEqual(scene.sideRoads.count, 12)
        XCTAssertTrue(scene.sideRoads.allSatisfy { $0.points.count == 2 })
    }

    func testKeepsAndClipsARoadThatCrossesTheRouteBetweenFarEndpoints() throws {
        let route = RoutePlan(
            points: [
                GeoPoint(latitude: 10, longitude: 106),
                GeoPoint(latitude: 10.004, longitude: 106),
            ],
            instructions: [],
            distanceMeters: 444
        )
        let crossingRoad = RoadPolyline(points: [
            GeoPoint(latitude: 10.002, longitude: 105.99),
            GeoPoint(latitude: 10.002, longitude: 106.01),
        ], isMajor: true)

        let scene = try RouteCardBuilder.build(route: route, progressIndex: 0, sideRoads: [crossingRoad])

        let road = try XCTUnwrap(scene.sideRoads.first)
        XCTAssertEqual(scene.sideRoads.count, 1)
        XCTAssertEqual(road.points.first?.x, 0)
        XCTAssertEqual(road.points.last?.x, 211)
        XCTAssertEqual(road.points.first?.y, road.points.last?.y)
    }

    func testRasterKeepsUpcomingRouteAboveSideRoads() throws {
        let route = RoutePlan(
            points: [GeoPoint(latitude: 10, longitude: 106), GeoPoint(latitude: 10.003, longitude: 106)],
            instructions: [],
            distanceMeters: 333
        )
        let road = RoadPolyline(points: [
            GeoPoint(latitude: 10.0015, longitude: 105.999),
            GeoPoint(latitude: 10.0015, longitude: 106.001),
        ], isMajor: true)
        let scene = try RouteCardBuilder.build(route: route, progressIndex: 0, sideRoads: [road])
        let raster = try IndexedRaster.render(routeCard: scene)

        XCTAssertEqual(raster.pixel(x: scene.marker.x, y: scene.marker.y - 20), IndexedRaster.Palette.route.rawValue)
    }

    func testProjectsLiveMarkerIntoThePublishedScene() throws {
        let route = RoutePlan(
            points: [GeoPoint(latitude: 10, longitude: 106), GeoPoint(latitude: 10.004, longitude: 106)],
            instructions: [], distanceMeters: 444
        )
        let marker = try XCTUnwrap(RouteCardBuilder.marker(
            route: route,
            anchorProgressIndex: 0,
            location: GeoPoint(latitude: 10.001, longitude: 106)
        ))
        XCTAssertEqual(marker.x, 106)
        XCTAssertLessThan(marker.y, 320)
        XCTAssertGreaterThan(marker.y, 200)
        XCTAssertNil(RouteCardBuilder.marker(
            route: route,
            anchorProgressIndex: 0,
            location: GeoPoint(latitude: 10.02, longitude: 106)
        ))
    }
}
