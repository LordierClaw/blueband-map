import XCTest
@testable import BlueBandProtocol

final class ThirdPartyAppCodecTests: XCTestCase {
    private let identity = ThirdPartyAppIdentity(
        packageName: "demo",
        fingerprint: Data([0x01, 0x02, 0x03, 0x04])
    )

    func testDecodesStatusRequestWithPackageAndFingerprint() throws {
        let command = try BandCommand.decode(
            Data(testHex: "08141006b2010e2a0c0a0464656d6f120401020304")
        )

        XCTAssertEqual(try ThirdPartyAppCodec.decode(command), .statusRequest(identity))
    }

    func testDecodesWearMessageWithOpaqueContent() throws {
        let command = try BandCommand.decode(
            Data(testHex: "08141009b201164a140a0c0a0464656d6f120401020304120450494e47")
        )

        XCTAssertEqual(
            try ThirdPartyAppCodec.decode(command),
            .wearMessage(identity: identity, content: Data("PING".utf8))
        )
    }

    func testEncodesConnectedStatusExactly() {
        XCTAssertEqual(
            ThirdPartyAppCodec.status(identity: identity, connected: true).encode(),
            Data(testHex: "08141007b2011242100a0c0a0464656d6f1204010203041001")
        )
    }

    func testEncodesPhoneMessageExactly() {
        XCTAssertEqual(
            ThirdPartyAppCodec.phoneMessage(identity: identity, content: Data("PING".utf8)).encode(),
            Data(testHex: "08141008b201164a140a0c0a0464656d6f120401020304120450494e47")
        )
    }

    func testRejectsWrongTypeAndMalformedIdentity() throws {
        XCTAssertThrowsError(
            try ThirdPartyAppCodec.decode(BandCommand(type: 2, subtype: 6, bodyField: 22, body: Data()))
        )
        let emptyFingerprint = try BandCommand.decode(
            Data(testHex: "08141006b2010a2a080a0464656d6f1200")
        )
        XCTAssertThrowsError(try ThirdPartyAppCodec.decode(emptyFingerprint))
    }
}
