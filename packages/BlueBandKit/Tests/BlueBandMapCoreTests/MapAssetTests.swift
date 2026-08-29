import Foundation
import XCTest
@testable import BlueBandMapCore

final class MapAssetTests: XCTestCase {
    func testPNGAcceptsValidNonZeroIndexDataSlice() throws {
        let prefixedData = Data([0xff]) + pngData(width: 212, height: 360)
        let slice = prefixedData.dropFirst()

        XCTAssertNotEqual(slice.startIndex, 0)
        let asset = try MapAsset.png(data: slice, expectedWidth: 212, expectedHeight: 360)

        XCTAssertEqual(asset.width, 212)
        XCTAssertEqual(asset.height, 360)
    }

    func testPNGIdentifiesDimensionsContentAndStableDigest() throws {
        let data = pngData(width: 212, height: 360)

        let first = try MapAsset.png(data: data, expectedWidth: 212, expectedHeight: 360)
        let second = try MapAsset.png(data: data, expectedWidth: 212, expectedHeight: 360)

        XCTAssertEqual(first.mimeType, "image/png")
        XCTAssertEqual(first.width, 212)
        XCTAssertEqual(first.height, 360)
        XCTAssertEqual(first.data, data)
        XCTAssertEqual(first.byteCount, data.count)
        XCTAssertNotNil(first.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression))
        XCTAssertEqual(first.sha256, "aa2a20ba1a365b558af3f4f3ca630e2336866f910a2b3ac23dac000b64f84c8f")
        XCTAssertEqual(first.id, "m1-aa2a20ba1a365b55")
        XCTAssertEqual(second.sha256, first.sha256)
        XCTAssertEqual(second.id, first.id)
    }

    func testPNGRejectsInvalidSignature() {
        var data = pngData(width: 212, height: 360)
        data[0] = 0

        XCTAssertThrowsError(try MapAsset.png(data: data, expectedWidth: 212, expectedHeight: 360)) { error in
            XCTAssertEqual(error as? MapAsset.Error, .invalidPNG)
        }
    }

    func testPNGRejectsTruncatedHeaderAsInvalidPNG() {
        XCTAssertThrowsError(try MapAsset.png(data: Data([137]), expectedWidth: 212, expectedHeight: 360)) { error in
            XCTAssertEqual(error as? MapAsset.Error, .invalidPNG)
        }
    }

    func testPNGRejectsIncorrectIHDRLengthAsInvalidPNG() {
        var data = pngData(width: 212, height: 360)
        data[11] = 12

        XCTAssertThrowsError(try MapAsset.png(data: data, expectedWidth: 212, expectedHeight: 360)) { error in
            XCTAssertEqual(error as? MapAsset.Error, .invalidPNG)
        }
    }

    func testPNGRejectsTruncatedIHDRPayloadAsInvalidPNG() {
        let data = pngData(width: 212, height: 360).prefix(28)

        XCTAssertThrowsError(try MapAsset.png(data: data, expectedWidth: 212, expectedHeight: 360)) { error in
            XCTAssertEqual(error as? MapAsset.Error, .invalidPNG)
        }
    }

    func testPNGRejectsWrongDimensions() {
        let data = pngData(width: 212, height: 360)

        XCTAssertThrowsError(try MapAsset.png(data: data, expectedWidth: 211, expectedHeight: 360)) { error in
            XCTAssertEqual(error as? MapAsset.Error, .wrongDimensions)
        }
    }

    func testPNGRejectsEmptyData() {
        XCTAssertThrowsError(try MapAsset.png(data: Data(), expectedWidth: 212, expectedHeight: 360)) { error in
            XCTAssertEqual(error as? MapAsset.Error, .empty)
        }
    }

    func testPNGRejectsDataAboveMaximumSize() {
        let data = Data(repeating: 0, count: MapAsset.maximumPNGBytes + 1)

        XCTAssertThrowsError(try MapAsset.png(data: data, expectedWidth: 212, expectedHeight: 360)) { error in
            XCTAssertEqual(error as? MapAsset.Error, .tooLarge)
        }
    }

    func testPNGAcceptsDataAtMaximumSize() throws {
        var data = pngData(width: 212, height: 360)
        data.append(Data(repeating: 0, count: MapAsset.maximumPNGBytes - data.count))

        let asset = try MapAsset.png(data: data, expectedWidth: 212, expectedHeight: 360)

        XCTAssertEqual(asset.byteCount, MapAsset.maximumPNGBytes)
        XCTAssertEqual(asset.data, data)
    }
}

private func pngData(width: UInt32, height: UInt32) -> Data {
    var bytes: [UInt8] = [
        137, 80, 78, 71, 13, 10, 26, 10,
        0, 0, 0, 13,
        73, 72, 68, 82,
    ]
    bytes.append(contentsOf: bigEndianBytes(width))
    bytes.append(contentsOf: bigEndianBytes(height))
    bytes.append(contentsOf: [8, 6, 0, 0, 0])
    return Data(bytes)
}

private func bigEndianBytes(_ value: UInt32) -> [UInt8] {
    [
        UInt8((value >> 24) & 0xff),
        UInt8((value >> 16) & 0xff),
        UInt8((value >> 8) & 0xff),
        UInt8(value & 0xff),
    ]
}
