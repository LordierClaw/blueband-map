import Foundation
import XCTest
@testable import BlueBandMapCore

final class MapAssetTests: XCTestCase {
    func testPNGIdentifiesDimensionsContentAndStableDigest() throws {
        let data = pngData(width: 212, height: 360)

        let first = try MapAsset.png(data: data, expectedWidth: 212, expectedHeight: 360)
        let second = try MapAsset.png(data: data, expectedWidth: 212, expectedHeight: 360)

        XCTAssertEqual(first.mimeType, "image/png")
        XCTAssertEqual(first.width, 212)
        XCTAssertEqual(first.height, 360)
        XCTAssertEqual(first.byteCount, data.count)
        XCTAssertNotNil(first.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression))
        XCTAssertEqual(first.id, "m1-" + String(first.sha256.prefix(16)))
        XCTAssertEqual(second.sha256, first.sha256)
        XCTAssertEqual(second.id, first.id)
    }

    func testPNGRejectsInvalidSignature() {
        var data = pngData(width: 212, height: 360)
        data[0] = 0

        XCTAssertThrowsError(try MapAsset.png(data: data, expectedWidth: 212, expectedHeight: 360))
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
