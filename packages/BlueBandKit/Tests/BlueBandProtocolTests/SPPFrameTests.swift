import XCTest
@testable import BlueBandProtocol

final class SPPFrameTests: XCTestCase {
    private let literalFrame = Data([0xA5, 0xA5, 0x03, 0x07, 0x04, 0x00, 0x96, 0x3C,
                                     0x01, 0x01, 0x08, 0x01])

    func testEncodingUsesLittleEndianLengthAndCRC() throws {
        let frame = SPPFrame(packetType: .data, sequence: 7, payload: Data([1, 1, 8, 1]))

        XCTAssertEqual(try frame.encode(), literalFrame)
    }

    func testDecodingLiteralFramePreservesFields() throws {
        let decoded = try SPPFrame.decode(literalFrame)

        XCTAssertEqual(decoded.packetType, .data)
        XCTAssertEqual(decoded.sequence, 7)
        XCTAssertEqual(decoded.payload, Data([1, 1, 8, 1]))
    }

    func testDecodingIgnoresTransportFlagsInUpperTypeNibble() throws {
        var flagged = literalFrame
        flagged[2] = 0x83

        XCTAssertEqual(try SPPFrame.decode(flagged).packetType, .data)
    }

    func testRejectsBadMagic() {
        var bytes = literalFrame
        bytes[0] = 0

        XCTAssertThrowsError(try SPPFrame.decode(bytes)) { error in
            XCTAssertEqual(error as? SPPFrame.Error, .invalidMagic)
        }
    }

    func testRejectsTruncatedAndTrailingData() {
        XCTAssertThrowsError(try SPPFrame.decode(literalFrame.dropLast()))
        XCTAssertThrowsError(try SPPFrame.decode(literalFrame + Data([0])))
    }

    func testRejectsBadCRC() {
        var bytes = literalFrame
        bytes[8] ^= 0xFF

        XCTAssertThrowsError(try SPPFrame.decode(bytes)) { error in
            XCTAssertEqual(error as? SPPFrame.Error, .invalidCRC)
        }
    }

    func testRejectsUnknownPacketType() {
        var bytes = literalFrame
        bytes[2] = 0xFF

        XCTAssertThrowsError(try SPPFrame.decode(bytes)) { error in
            XCTAssertEqual(error as? SPPFrame.Error, .unknownPacketType)
        }
    }
}
