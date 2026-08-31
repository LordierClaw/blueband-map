import Foundation
import XCTest
@testable import BlueBandMapCore

final class VietmapSceneBuilderTests: XCTestCase {
    func testProjectsAndClipsRoadGeometryIntoTheViewport() throws {
        let tile = try MapboxVectorTile.decode(VectorTileFixture.lineTile(
            points: [VectorTileFixture.Point(x: 1_000, y: 2_048), VectorTileFixture.Point(x: 3_100, y: 2_048)]
        ))
        let scene = try VietmapSceneBuilder.build(
            tile: tile,
            latitude: 0,
            longitude: 0,
            zoom: 0,
            tileX: 0,
            tileY: 0,
            headingDegrees: 0,
            maneuver: .straight,
            distanceMeters: 20
        )

        XCTAssertFalse(scene.segments.isEmpty)
        XCTAssertTrue(scene.segments.allSatisfy {
            $0.start.x < 212 && $0.start.y < 360 && $0.end.x < 212 && $0.end.y < 360
        })
        XCTAssertEqual(scene.segments.first?.lineClass, .major)
    }

    func testScalesMVTCoordinatesToScreenPixels() throws {
        let tile = try MapboxVectorTile.decode(VectorTileFixture.lineTile(
            points: [VectorTileFixture.Point(x: 1_888, y: 2_048), VectorTileFixture.Point(x: 2_208, y: 2_048)]
        ))
        let scene = try VietmapSceneBuilder.build(
            tile: tile,
            latitude: 0,
            longitude: 0,
            zoom: 0,
            tileX: 0,
            tileY: 0,
            headingDegrees: 0,
            maneuver: .straight,
            distanceMeters: 20
        )

        XCTAssertEqual(scene.segments.first?.start, ScenePoint(x: 96, y: 180))
        XCTAssertEqual(scene.segments.first?.end, ScenePoint(x: 116, y: 180))
    }

    func testKeepsOnlyStyleSelectedRoadLayers() throws {
        let road = try MapboxVectorTile.decode(VectorTileFixture.lineTile(
            layerName: "road",
            points: [VectorTileFixture.Point(x: 1_800, y: 2_048), VectorTileFixture.Point(x: 2_300, y: 2_048)]
        ))
        let boundary = try MapboxVectorTile.decode(VectorTileFixture.lineTile(
            layerName: "boundary",
            points: [VectorTileFixture.Point(x: 2_048, y: 1_800), VectorTileFixture.Point(x: 2_048, y: 2_300)]
        ))
        let scene = try VietmapSceneBuilder.build(
            tiles: [road, boundary],
            sourceLayers: ["road"],
            latitude: 0,
            longitude: 0,
            zoom: 0,
            tileX: 0,
            tileY: 0,
            headingDegrees: 0,
            maneuver: .straight,
            distanceMeters: 20
        )

        XCTAssertEqual(scene.segments.count, 1)
        XCTAssertEqual(scene.segments[0].start.y, scene.segments[0].end.y)
    }

    func testReducesToFortyAndRetainsRouteSegmentsFirst() throws {
        let tiles = try (0..<50).map { index in
            try MapboxVectorTile.decode(VectorTileFixture.lineTile(
                classValue: index == 49 ? "route" : "residential",
                points: [
                    VectorTileFixture.Point(x: 1_000 + index * 40, y: 2_000),
                    VectorTileFixture.Point(x: 1_032 + index * 40, y: 2_032),
                ]
            ))
        }
        let scene = try VietmapSceneBuilder.build(
            tiles: tiles,
            latitude: 0,
            longitude: 0,
            zoom: 0,
            tileX: 0,
            tileY: 0,
            headingDegrees: 180,
            maneuver: .left,
            distanceMeters: 100,
            maximumSegments: 40
        )

        XCTAssertEqual(scene.segments.count, 40)
        XCTAssertEqual(scene.segments.first?.lineClass, .route)
    }

    func testPrefersNearbyStreetsOverDistantMajorRoads() throws {
        let distantMajorRoads = try (0..<40).map { index in
            try MapboxVectorTile.decode(VectorTileFixture.lineTile(
                classValue: "primary",
                points: [
                    VectorTileFixture.Point(x: 500 + index, y: 2_000),
                    VectorTileFixture.Point(x: 532 + index, y: 2_032),
                ]
            ))
        }
        let nearbyStreet = try MapboxVectorTile.decode(VectorTileFixture.lineTile(
            classValue: "minor",
            points: [
                VectorTileFixture.Point(x: 2_000, y: 2_048),
                VectorTileFixture.Point(x: 2_096, y: 2_048),
            ]
        ))

        let scene = try VietmapSceneBuilder.build(
            tiles: distantMajorRoads + [nearbyStreet],
            latitude: 0,
            longitude: 0,
            zoom: 0,
            tileX: 0,
            tileY: 0,
            headingDegrees: 0,
            maneuver: .straight,
            distanceMeters: 0,
            maximumSegments: 40
        )

        XCTAssertTrue(scene.segments.contains { $0.lineClass == .minor })
    }

    func testOmitsWalkingPathsFromTheStreetMap() throws {
        let path = try MapboxVectorTile.decode(VectorTileFixture.lineTile(
            classValue: "path",
            points: [
                VectorTileFixture.Point(x: 2_000, y: 2_048),
                VectorTileFixture.Point(x: 2_096, y: 2_048),
            ]
        ))
        let road = try MapboxVectorTile.decode(VectorTileFixture.lineTile(
            classValue: "minor",
            points: [
                VectorTileFixture.Point(x: 2_048, y: 2_000),
                VectorTileFixture.Point(x: 2_048, y: 2_096),
            ]
        ))

        let scene = try VietmapSceneBuilder.build(
            tiles: [path, road],
            latitude: 0,
            longitude: 0,
            zoom: 0,
            tileX: 0,
            tileY: 0,
            headingDegrees: 0,
            maneuver: .straight,
            distanceMeters: 0
        )

        XCTAssertEqual(scene.segments.count, 1)
        XCTAssertEqual(scene.segments[0].start.x, scene.segments[0].end.x)
    }

    func testExtendsAConnectedRoadBeforeAddingDetachedFragments() throws {
        let seed = try MapboxVectorTile.decode(VectorTileFixture.lineTile(
            classValue: "minor",
            points: [
                VectorTileFixture.Point(x: 2_000, y: 2_048),
                VectorTileFixture.Point(x: 2_096, y: 2_048),
            ]
        ))
        let extensionRoad = try MapboxVectorTile.decode(VectorTileFixture.lineTile(
            classValue: "minor",
            points: [
                VectorTileFixture.Point(x: 2_096, y: 2_048),
                VectorTileFixture.Point(x: 3_000, y: 2_048),
            ]
        ))
        let detached = try (0..<39).map { index in
            try MapboxVectorTile.decode(VectorTileFixture.lineTile(
                classValue: "minor",
                points: [
                    VectorTileFixture.Point(x: 2_000, y: 1_850 + index),
                    VectorTileFixture.Point(x: 2_096, y: 1_850 + index),
                ]
            ))
        }

        let scene = try VietmapSceneBuilder.build(
            tiles: [seed, extensionRoad] + detached,
            latitude: 0,
            longitude: 0,
            zoom: 0,
            tileX: 0,
            tileY: 0,
            headingDegrees: 0,
            maneuver: .straight,
            distanceMeters: 0,
            maximumSegments: 40
        )

        XCTAssertEqual(scene.segments.count, 40)
        XCTAssertTrue(scene.segments.contains {
            $0.start.y == $0.end.y && Int($0.end.x) - Int($0.start.x) > 40
        })
    }

    func testCollapsesNearlyStraightRoadGeometryBeforeApplyingThePrimitiveLimit() throws {
        let tile = try MapboxVectorTile.decode(VectorTileFixture.lineTile(
            classValue: "minor",
            points: (0..<20).map { index in
                VectorTileFixture.Point(x: 1_000 + index * 100, y: 2_048 + index % 2)
            }
        ))

        let scene = try VietmapSceneBuilder.build(
            tile: tile,
            latitude: 0,
            longitude: 0,
            zoom: 0,
            tileX: 0,
            tileY: 0,
            headingDegrees: 0,
            maneuver: .straight,
            distanceMeters: 0
        )

        XCTAssertLessThanOrEqual(scene.segments.count, 2)
    }

    func testSupportsAnExplicitSixtyPrimitiveStressBudget() throws {
        let tiles = try (0..<70).map { index in
            try MapboxVectorTile.decode(VectorTileFixture.lineTile(
                classValue: "minor",
                points: [
                    VectorTileFixture.Point(x: 1_000 + index * 30, y: 1_900),
                    VectorTileFixture.Point(x: 1_020 + index * 30, y: 1_940),
                ]
            ))
        }

        let scene = try VietmapSceneBuilder.build(
            tiles: tiles,
            latitude: 0,
            longitude: 0,
            zoom: 0,
            tileX: 0,
            tileY: 0,
            headingDegrees: 0,
            maneuver: .straight,
            distanceMeters: 0,
            maximumSegments: 60
        )

        XCTAssertEqual(scene.segments.count, 60)
    }

    func testDoesNotMagnifyASelectedRoadNetworkAwayFromItsMapCoordinates() throws {
        let tiles = try (0..<8).map { index in
            try MapboxVectorTile.decode(VectorTileFixture.lineTile(
                classValue: "minor",
                points: [
                    VectorTileFixture.Point(x: 2_000, y: 2_000 + index * 10),
                    VectorTileFixture.Point(x: 2_096, y: 2_000 + index * 10),
                ]
            ))
        }

        let scene = try VietmapSceneBuilder.build(
            tiles: tiles,
            latitude: 0,
            longitude: 0,
            zoom: 0,
            tileX: 0,
            tileY: 0,
            headingDegrees: 0,
            maneuver: .straight,
            distanceMeters: 0,
            maximumSegments: 8
        )

        XCTAssertTrue(scene.segments.contains {
            $0.start == ScenePoint(x: 103, y: 177) && $0.end == ScenePoint(x: 109, y: 177)
        })
    }
}
