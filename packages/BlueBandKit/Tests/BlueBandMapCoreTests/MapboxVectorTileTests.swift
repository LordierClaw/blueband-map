import Foundation
import XCTest
@testable import BlueBandMapCore

final class MapboxVectorTileTests: XCTestCase {
    func testVietmapPOCTileBudgetFitsTheObservedLegacyTile() {
        XCTAssertEqual(MapboxVectorTile.maximumBodyBytes, 3 * 1_024 * 1_024)
        XCTAssertEqual(MapboxVectorTile.maximumFeatures, 40_000)
    }
    func testDecodesVietmapXOREncodedTile() throws {
        let plain = VectorTileFixture.lineTile()
        let encoded = vietmapXOR(plain)

        XCTAssertThrowsError(try MapboxVectorTile.decode(encoded))
        let tile = try VietmapVectorTileDecoder.decode(encoded)

        XCTAssertFalse(tile.layers.isEmpty)
    }

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
            VectorTileFixture.Point(x: -4_097, y: 10),
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
        layer.append(contentsOf: [0x0a, 0x04])
        layer.append(contentsOf: Data("road".utf8))
        layer.append(contentsOf: [0x12, 0x02, 0x18, 0x01])
        var tile = Data([0x1a, UInt8(layer.count)])
        tile.append(layer)
        XCTAssertNoThrow(try MapboxVectorTile.decode(tile))

        let overflowingCommand = (UInt64(16_385) << 3) | 1
        XCTAssertThrowsError(try MapboxVectorTile.decode(VectorTileFixture.malformedGeometryTile(command: overflowingCommand))) { error in
            XCTAssertEqual(error as? MapboxVectorTile.Error, .tooManyGeometryCommands)
        }
    }
}

private func vietmapXOR(_ data: Data) -> Data {
    let key: [UInt8] = [
        80, 88, 228, 30, 157, 170, 173, 154, 233, 247, 128, 170, 135, 27, 48, 165,
        148, 251, 99, 44, 105, 248, 18, 145, 34, 163, 70, 114, 228, 184, 229, 72,
    ]
    return Data(data.enumerated().map { index, byte in byte ^ key[index % key.count] })
}
