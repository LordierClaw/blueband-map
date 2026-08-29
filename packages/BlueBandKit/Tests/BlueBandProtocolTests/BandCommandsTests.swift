import XCTest
@testable import BlueBandProtocol

final class BandCommandsTests: XCTestCase {
    func testBareProofRequestsHaveOnlyTypeAndSubtype() {
        XCTAssertEqual(BandCommands.batteryRequest.encode(), Data([0x08, 0x02, 0x10, 0x01]))
        XCTAssertEqual(BandCommands.deviceInfoRequest.encode(), Data([0x08, 0x02, 0x10, 0x02]))
        XCTAssertEqual(BandCommands.deviceStateRequest.encode(), Data([0x08, 0x02, 0x10, 0x4E]))
    }

    func testPhoneNonceUsesAuthFieldThirtyAndNonceFieldOne() {
        let nonce = Data((0..<16).map(UInt8.init))
        let literal = Data([0x08, 0x01, 0x10, 0x1A, 0x1A, 0x15, 0xF2, 0x01, 0x12, 0x0A, 0x10]) + nonce

        XCTAssertEqual(BandCommands.phoneNonce(nonce).encode(), literal)
    }

    func testAuthStepThreeUsesAuthFieldThirtyTwo() {
        let command = BandCommands.authStep3(
            encryptedNonces: Data([0xAA, 0xBB]),
            encryptedDeviceInfo: Data([0xCC])
        )

        XCTAssertEqual(command.encode(), Data([
            0x08, 0x01, 0x10, 0x1B,
            0x1A, 0x0A,
            0x82, 0x02, 0x07,
            0x0A, 0x02, 0xAA, 0xBB,
            0x12, 0x01, 0xCC
        ]))
    }

    func testParsesWatchNonceAndHMACFromLiteralResponse() throws {
        let nonce = Data((0..<16).map(UInt8.init))
        let hmac = Data(repeating: 0xAA, count: 32)
        let response = Data([0x08, 0x01, 0x10, 0x1A, 0x1A, 0x37, 0xFA, 0x01, 0x34,
                             0x0A, 0x10]) + nonce + Data([0x12, 0x20]) + hmac

        let parsed = try BandCommands.parseWatchNonce(BandCommand.decode(response))

        XCTAssertEqual(parsed, WatchNonce(nonce: nonce, hmac: hmac))
    }

    func testRejectsWatchNonceWithWrongLengths() throws {
        let shortResponse = Data([0x08, 0x01, 0x10, 0x1A, 0x1A, 0x08, 0xFA, 0x01, 0x05,
                                  0x0A, 0x01, 0x01, 0x12, 0x00])

        XCTAssertThrowsError(try BandCommands.parseWatchNonce(BandCommand.decode(shortResponse)))
    }

    func testDecodesBatteryNestedUnderSystemPower() throws {
        let response = Data([0x08, 0x02, 0x10, 0x01, 0x22, 0x08,
                             0x12, 0x06, 0x0A, 0x04, 0x08, 0x57, 0x10, 0x02])

        XCTAssertEqual(try BandBattery.decode(BandCommand.decode(response)),
                       BandBattery(level: 87, state: 2))
    }

    func testDecodesDeviceInfoAndIgnoresUnknownField() throws {
        let response = Data([0x08, 0x02, 0x10, 0x02, 0x22, 0x12,
                             0x1A, 0x10,
                             0x0A, 0x02, 0x53, 0x4E,
                             0x12, 0x03, 0x31, 0x2E, 0x30,
                             0x18, 0x63,
                             0x22, 0x03, 0x4D, 0x31, 0x30])

        XCTAssertEqual(try BandDeviceInfo.decode(BandCommand.decode(response)),
                       BandDeviceInfo(serial: "SN", firmware: "1.0", model: "M10"))
    }

    func testTopLevelStatusFieldIsPreserved() throws {
        let response = Data([0x08, 0x01, 0x10, 0x1B, 0xA0, 0x06, 0x03])

        XCTAssertEqual(try BandCommand.decode(response).status, 3)
    }

    func testAuthDeviceInfoIdentifiesIOSAndAllCapabilities() {
        let encoded = BandCommands.authDeviceInfo(
            apiLevel: 17,
            phoneName: "BlueBand iPhone",
            region: "US"
        )

        XCTAssertEqual(encoded, Data(testHex: """
            0801
            1500008841
            1a0f426c756542616e64206950686f6e65
            20ffffffff0f
            2a025553
        """))
    }

    func testAuthStatusReadsNestedAuthStatusWhenTopLevelIsAbsent() throws {
        var auth = ProtoWriter()
        auth.putVarint(field: 8, value: 5)
        let command = BandCommand(type: 1, subtype: 27, bodyField: 3, body: auth.data)

        XCTAssertEqual(try BandCommands.authStatus(command), 5)
    }
}
