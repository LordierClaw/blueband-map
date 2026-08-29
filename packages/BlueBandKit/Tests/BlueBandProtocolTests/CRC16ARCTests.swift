import XCTest
@testable import BlueBandProtocol

final class CRC16ARCTests: XCTestCase {
    func testStandardCheckVectorDetectsWrongPolynomialOrBitOrder() {
        XCTAssertEqual(CRC16ARC.checksum(Data("123456789".utf8)), 0xBB3D)
    }

    func testEmptyPayloadStartsAtZero() {
        XCTAssertEqual(CRC16ARC.checksum(Data()), 0)
    }
}
