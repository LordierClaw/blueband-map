import XCTest
@testable import BlueBandProtocol

final class AuthKeyTests: XCTestCase {
    func testParsesSixteenBytesFromThirtyTwoHexCharacters() throws {
        let key = try AuthKey(hex: String(repeating: "aF", count: 16))

        XCTAssertEqual(key.bytes, Data(repeating: 0xAF, count: 16))
    }

    func testTrimsOnlySurroundingWhitespace() throws {
        let key = try AuthKey(hex: "  \n" + String(repeating: "01", count: 16) + "\t")

        XCTAssertEqual(key.bytes, Data(repeating: 0x01, count: 16))
    }

    func testRejectsWrongLength() {
        XCTAssertThrowsError(try AuthKey(hex: "00")) { error in
            XCTAssertEqual(error as? AuthKey.ValidationError, .invalidLength)
        }
    }

    func testRejectsNonHexCharacters() {
        XCTAssertThrowsError(try AuthKey(hex: String(repeating: "xz", count: 16))) { error in
            XCTAssertEqual(error as? AuthKey.ValidationError, .invalidHex)
        }
    }

    func testRejectsWhitespaceInsideKey() {
        let value = String(repeating: "00", count: 8) + " " + String(repeating: "00", count: 8)

        XCTAssertThrowsError(try AuthKey(hex: value))
    }
}
