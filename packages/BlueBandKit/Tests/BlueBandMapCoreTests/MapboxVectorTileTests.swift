import Foundation
import XCTest
@testable import BlueBandMapCore

final class MapboxVectorTileTests: XCTestCase {
    func testPolygonPreservesExteriorAndHoleRingsForCPUFills() throws {
        // Independent MVT commands: outer clockwise square and inner counterclockwise hole.
        let data = geometryTile(type: 3, commands: [
            9, 0, 0, 26, 20, 0, 0, 20, 19, 0, 15,
            9, 6, 13, 26, 0, 8, 8, 0, 0, 7, 15,
        ])
        let feature = try XCTUnwrap(MapboxVectorTile.decode(data).layers.first?.features.first)
        XCTAssertEqual(feature.lines.count, 2, "buildings/water must not be discarded as non-road geometry")
        XCTAssertEqual(feature.lines.first?.map { [$0.x, $0.y] }, [[0,0],[10,0],[10,10],[0,10],[0,0]])
        XCTAssertEqual(feature.lines.last?.map { [$0.x, $0.y] }, [[3,3],[3,7],[7,7],[7,3],[3,3]])
    }

    func testPointFeaturesKeepTheirCoordinates() throws {
        let tile = try MapboxVectorTile.decode(geometryTile(type: 1, commands: [17,6,8,4,4]))
        XCTAssertEqual(tile.layers.first?.features.first?.lines.map { $0.map { [$0.x, $0.y] } }, [[[3,4]],[[5,6]]])
    }

    func testRejectsUnclosedOrInvalidPolygonRing() {
        for commands: [UInt8] in [[9,0,0,26,20,0,0,20,19,0], [9,0,0,10,20,0,15], [9,0,0,26,20,0,0,20,19,0,23]] {
            XCTAssertThrowsError(try MapboxVectorTile.decode(geometryTile(type: 3, commands: commands)))
        }
    }

    private func geometryTile(type: UInt8, commands: [UInt8]) -> Data {
        let feature = [UInt8(0x18), type, 0x22, UInt8(commands.count)] + commands
        let layer = [UInt8(0x0a), 8] + Array("building".utf8) + [0x12, UInt8(feature.count)] + feature
        return Data([0x1a, UInt8(layer.count)] + layer)
    }

    func testVietmapDecoderAcceptsCurrentRawVectorTiles() throws {
        let raw = VectorTileFixture.lineTile(
            points: [VectorTileFixture.Point(x: 1_000, y: 2_000), VectorTileFixture.Point(x: 2_000, y: 2_000)]
        )

        let tile = try VietmapVectorTileDecoder.decode(raw)

        XCTAssertEqual(tile.layers.first?.name, "road")
    }

    func testVietmapDecoderStripsCurrentThreeByteTransformMarker() throws {
        let raw = VectorTileFixture.lineTile(
            points: [VectorTileFixture.Point(x: 1_000, y: 2_000), VectorTileFixture.Point(x: 2_000, y: 2_000)]
        )
        var encoded = Data([1, 1, 1])
        encoded.append(vietmapCurrentXOR(raw))

        let tile = try VietmapVectorTileDecoder.decode(encoded)

        XCTAssertEqual(tile.layers.first?.features.first?.lines.first?.count, 2)
    }

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

private func vietmapCurrentXOR(_ data: Data) -> Data {
    let key: [UInt8] = [
        1, 2, 3, 5, 7, 9, 15, 60, 45, 95, 45, 69, 78, 42, 66, 54,
        99, 57, 54, 33, 22, 11, 66, 99, 99, 77, 55, 23, 45, 65, 72, 35,
    ]
    return Data(data.enumerated().map { index, byte in byte ^ key[index % key.count] })
}
