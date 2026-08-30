import Foundation
import XCTest
@testable import BlueBandMapCore

final class MapboxVectorTileTests: XCTestCase {
    func testDecodesLineGeometryTagsAndZigZagCoordinates() throws {
        let tile = try MapboxVectorTile.decode(VectorTileFixture.lineTile())
        let layer = try XCTUnwrap(tile.layers.first)
        let feature = try XCTUnwrap(layer.features.first)

        XCTAssertEqual(layer.name, "road")
        XCTAssertEqual(layer.extent, 4_096)
        XCTAssertEqual(feature.geometryType, .lineString)
        XCTAssertEqual(feature.properties["class"], "primary")
        let points = try XCTUnwrap(feature.lines.first)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0], MapboxVectorTile.TilePoint(x: 1_800, y: 1_800))
        XCTAssertEqual(points[1], MapboxVectorTile.TilePoint(x: 2_300, y: 2_300))
    }

    func testRejectsTruncatedVarintUnsupportedCommandAndOutOfExtentCoordinate() {
        XCTAssertThrowsError(try MapboxVectorTile.decode(Data([0x1a, 0x80]))) { error in
            XCTAssertEqual(error as? MapboxVectorTile.Error, .truncated)
        }

        XCTAssertThrowsError(try MapboxVectorTile.decode(VectorTileFixture.malformedGeometryTile(command: (1 << 3) | 3))) { error in
            XCTAssertEqual(error as? MapboxVectorTile.Error, .unsupportedGeometryCommand)
        }

        let outside = VectorTileFixture.lineTile(points: [
            VectorTileFixture.Point(x: -1, y: 10),
            VectorTileFixture.Point(x: 10, y: 10),
        ])
        XCTAssertThrowsError(try MapboxVectorTile.decode(outside)) { error in
            XCTAssertEqual(error as? MapboxVectorTile.Error, .coordinateOutOfExtent)
        }
    }

    func testIgnoresNonLineFeatureTypesButRejectsGeometryCommandOverflow() {
        var feature = Data()
        feature.append(contentsOf: [0x18, 0x01])
        var layer = Data()
        layer.append(contentsOf: [0x12, 0x04])
        layer.append(contentsOf: Data("road".utf8))
        layer.append(contentsOf: [0x1a, 0x02, 0x18, 0x01])
        var tile = Data([0x1a, UInt8(layer.count)])
        tile.append(layer)
        XCTAssertNoThrow(try MapboxVectorTile.decode(tile))

        let overflowingCommand = (UInt64(16_385) << 3) | 1
        XCTAssertThrowsError(try MapboxVectorTile.decode(VectorTileFixture.malformedGeometryTile(command: overflowingCommand))) { error in
            XCTAssertEqual(error as? MapboxVectorTile.Error, .tooManyGeometryCommands)
        }
    }
}
