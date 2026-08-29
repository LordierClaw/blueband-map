import CryptoSwift
import Foundation
import XCTest
import BlueBandCrypto
import BlueBandProtocol
@testable import BlueBandCore

final class BandAuthenticatorTests: XCTestCase {
    private let authKey = try! AuthKey(bytes: Data((0x00..<0x10).map(UInt8.init)))
    private let phoneNonce = Data((0x20..<0x30).map(UInt8.init))
    private let watchNonce = Data((0x30..<0x40).map(UInt8.init))

    func testSuccessfulTranscriptReturnsKeysAndSendsTwoSteps() async throws {
        let keys = try SessionCrypto.derive(authKey: authKey, phoneNonce: phoneNonce, watchNonce: watchNonce)
        let watchHMAC = SessionCrypto.hmacSHA256(message: watchNonce + phoneNonce, key: keys.decryptKey)
        let transport = ScriptedAuthTransport(responsesBySend: [
            [watchNonceMessage(hmac: watchHMAC)],
            [BandTransportMessage(channel: 1, opcode: 1, body: Data([0x08, 0x01, 0x10, 0x1B]))]
        ])
        let result = try await subject().authenticate(authKey: authKey, transport: transport)
        let sentCount = await transport.sentMessages.count
        XCTAssertEqual(result.keys, keys)
        XCTAssertEqual(sentCount, 2)
    }

    func testInvalidWatchHMACClosesTransport() async {
        let transport = ScriptedAuthTransport(responsesBySend: [
            [watchNonceMessage(hmac: Data(repeating: 0, count: 32))]
        ])
        do {
            _ = try await subject().authenticate(authKey: authKey, transport: transport)
            XCTFail("Expected mismatch")
        } catch {
            XCTAssertEqual(error as? BandAuthenticationError, .hmacMismatch)
        }
        let closed = await transport.isClosed
        XCTAssertTrue(closed)
    }

    func testTimeoutClosesTransport() async {
        let transport = ScriptedAuthTransport(responsesBySend: [])
        let subject = BandAuthenticator(
            timeout: .milliseconds(5),
            nonceGenerator: { self.phoneNonce },
            device: fixedDevice,
            cipher: CryptoSwiftAESBlockCipher()
        )
        do {
            _ = try await subject.authenticate(authKey: authKey, transport: transport)
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? BandAuthenticationError, .timeout)
        }
        let closed = await transport.isClosed
        XCTAssertTrue(closed)
    }

    private var fixedDevice: AuthDeviceDescriptor {
        AuthDeviceDescriptor(apiLevel: 17, phoneName: "BlueBandMap iPhone", region: "US")
    }

    private func subject() -> BandAuthenticator {
        BandAuthenticator(
            timeout: .seconds(1),
            nonceGenerator: { self.phoneNonce },
            device: fixedDevice,
            cipher: CryptoSwiftAESBlockCipher()
        )
    }

    private func watchNonceMessage(hmac: Data) -> BandTransportMessage {
        let authBody = Data([0xFA, 0x01, 0x34, 0x0A, 0x10]) + watchNonce + Data([0x12, 0x20]) + hmac
        return BandTransportMessage(
            channel: 1,
            opcode: 1,
            body: BandCommand(type: 1, subtype: 26, bodyField: 3, body: authBody).encode()
        )
    }
}

private struct CryptoSwiftAESBlockCipher: AESBlockCipher {
    func encrypt(block: Data, key: Data) throws -> Data {
        let aes = try AES(key: Array(key), blockMode: ECB(), padding: .noPadding)
        return Data(try aes.encrypt(Array(block)))
    }
}

private actor ScriptedAuthTransport: BandTransportProtocol {
    private let stream: AsyncThrowingStream<BandTransportMessage, Error>
    private let continuation: AsyncThrowingStream<BandTransportMessage, Error>.Continuation
    private var responsesBySend: [[BandTransportMessage]]
    private(set) var sentMessages: [BandTransportMessage] = []
    private(set) var isClosed = false

    init(responsesBySend: [[BandTransportMessage]]) {
        self.responsesBySend = responsesBySend
        var continuation: AsyncThrowingStream<BandTransportMessage, Error>.Continuation!
        stream = AsyncThrowingStream { continuation = $0 }
        self.continuation = continuation
    }

    func configure() async throws {}
    func send(channel: UInt8, opcode: UInt8, body: Data) async throws {
        sentMessages.append(BandTransportMessage(channel: channel, opcode: opcode, body: body))
        if !responsesBySend.isEmpty { responsesBySend.removeFirst().forEach { continuation.yield($0) } }
    }
    func incoming() async -> AsyncThrowingStream<BandTransportMessage, Error> { stream }
    func close() async { isClosed = true; continuation.finish() }
}
