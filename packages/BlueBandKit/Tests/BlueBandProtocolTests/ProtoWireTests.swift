import XCTest
@testable import BlueBandProtocol

final class ProtoWireTests: XCTestCase {
    func testWritesAndReadsSupportedWireTypesWithLiteralByteOrder() throws {
        var writer = ProtoWriter()
        writer.putVarint(field: 1, value: 300)
        writer.putBytes(field: 2, value: Data([0xAA, 0xBB]))
        writer.putFixed32(field: 3, value: 0x12345678)
        writer.putFixed64(field: 4, value: 0x0102030405060708)

        XCTAssertEqual(writer.data, Data([
            0x08, 0xAC, 0x02,
            0x12, 0x02, 0xAA, 0xBB,
            0x1D, 0x78, 0x56, 0x34, 0x12,
            0x21, 0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01
        ]))
        XCTAssertEqual(try ProtoReader(data: writer.data).allFields(), [
            .varint(number: 1, value: 300),
            .bytes(number: 2, value: Data([0xAA, 0xBB])),
            .fixed32(number: 3, value: 0x12345678),
            .fixed64(number: 4, value: 0x0102030405060708)
        ])
    }

    func testVarintBoundariesUseMinimumEncoding() {
        var writer = ProtoWriter()
        writer.putVarint(field: 1, value: 0)
        writer.putVarint(field: 1, value: 127)
        writer.putVarint(field: 1, value: 128)

        XCTAssertEqual(writer.data, Data([0x08, 0x00, 0x08, 0x7F, 0x08, 0x80, 0x01]))
    }

    func testRejectsTruncatedVarintAndLengthDelimitedField() {
        XCTAssertThrowsError(try ProtoReader(data: Data([0x08, 0x80])).allFields())
        XCTAssertThrowsError(try ProtoReader(data: Data([0x0A, 0x02, 0xAA])).allFields())
    }

    func testRejectsFieldZeroAndUnsupportedGroups() {
        XCTAssertThrowsError(try ProtoReader(data: Data([0x00])).allFields())
        XCTAssertThrowsError(try ProtoReader(data: Data([0x0B])).allFields())
    }

    func testRejectsVarintLongerThanTenBytes() {
        XCTAssertThrowsError(
            try ProtoReader(data: Data([UInt8(0x08)] + [UInt8](repeating: 0x80, count: 11))).allFields()
        )
    }
}
