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
            distanceMeters: 100
        )

        XCTAssertEqual(scene.segments.count, 40)
        XCTAssertEqual(scene.segments.first?.lineClass, .route)
    }
}
