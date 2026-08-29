import CryptoSwift
import Foundation
import XCTest
import BlueBandCrypto
import BlueBandProtocol
@testable import BlueBandCore

final class BandSessionTests: XCTestCase {
    private let authKey = try! AuthKey(bytes: Data((0x00..<0x10).map(UInt8.init)))
    private let phoneNonce = Data((0x20..<0x30).map(UInt8.init))
    private let watchNonce = Data((0x30..<0x40).map(UInt8.init))

    func testConnectRetriesOnceOnlyForInitialHMACMismatch() async throws {
        let keys = try SessionCrypto.derive(authKey: authKey, phoneNonce: phoneNonce, watchNonce: watchNonce)
        let hmac = SessionCrypto.hmacSHA256(message: watchNonce + phoneNonce, key: keys.decryptKey)
        let first = SessionTransport(responses: [[watchMessage(hmac: Data(repeating: 0, count: 32))]])
        let second = SessionTransport(responses: [
            [watchMessage(hmac: hmac)],
            [BandTransportMessage(channel: 1, opcode: 1, body: Data([0x08, 0x01, 0x10, 0x1B]))]
        ])
        let central = SessionCentral()
        let factory = TransportFactory([first, second])
        let session = makeSession(central: central, factory: factory)

        try await session.connect(
            candidate: BandCandidate(id: UUID(), name: "Xiaomi Smart Band 10", rssi: -42),
            authKey: authKey
        )

        let connectionCount = await central.count()
        let firstClosed = await first.closed()
        let secondClosed = await second.closed()
        let state = await session.state()
        XCTAssertEqual(connectionCount, 2)
        XCTAssertTrue(firstClosed)
        XCTAssertFalse(secondClosed)
        XCTAssertEqual(state, .readingDeviceProof)
    }

    func testDisconnectClearsKeysAndReturnsIdle() async throws {
        let keys = try SessionCrypto.derive(authKey: authKey, phoneNonce: phoneNonce, watchNonce: watchNonce)
        let hmac = SessionCrypto.hmacSHA256(message: watchNonce + phoneNonce, key: keys.decryptKey)
        let transport = SessionTransport(responses: [
            [watchMessage(hmac: hmac)],
            [BandTransportMessage(channel: 1, opcode: 1, body: Data([0x08, 0x01, 0x10, 0x1B]))]
        ])
        let session = makeSession(central: SessionCentral(), factory: TransportFactory([transport]))
        try await session.connect(candidate: BandCandidate(id: UUID(), name: "Band 10", rssi: -50), authKey: authKey)
        await session.disconnect()
        let state = await session.state()
        let closed = await transport.closed()
        XCTAssertEqual(state, .idle)
        XCTAssertTrue(closed)
        do {
            _ = try await session.requestProofData()
            XCTFail("Expected not connected")
        } catch {
            XCTAssertEqual(error as? BandSessionError, .notConnected)
        }
    }

    private func makeSession(central: SessionCentral, factory: TransportFactory) -> BandSession {
        let cipher = SessionAESBlockCipher()
        return BandSession(
            central: central,
            authenticator: BandAuthenticator(
                timeout: .seconds(1),
                nonceGenerator: { self.phoneNonce },
                device: AuthDeviceDescriptor(apiLevel: 17, phoneName: "BlueBandMap iPhone", region: "US"),
                cipher: cipher
            ),
            cipher: cipher,
            trustedRPKStore: SessionTrustStore(),
            transportFactory: { link in factory.make(link) }
        )
    }

    private func watchMessage(hmac: Data) -> BandTransportMessage {
        let authBody = Data([0xFA, 0x01, 0x34, 0x0A, 0x10]) + watchNonce + Data([0x12, 0x20]) + hmac
        return BandTransportMessage(
            channel: 1, opcode: 1,
            body: BandCommand(type: 1, subtype: 26, bodyField: 3, body: authBody).encode()
        )
    }
}

private struct SessionAESBlockCipher: AESBlockCipher {
    func encrypt(block: Data, key: Data) throws -> Data {
        Data(try AES(key: Array(key), blockMode: ECB(), padding: .noPadding).encrypt(Array(block)))
    }
}

private actor SessionTrustStore: TrustedRPKStore {
    private var value: Data?
    func trustedRPKFingerprint() async throws -> Data? { value }
    func saveTrustedRPKFingerprint(_ fingerprint: Data) async throws { value = fingerprint }
    func resetTrustedRPKFingerprint() async throws { value = nil }
}

private final class TransportFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var transports: [any BandTransportProtocol]
    init(_ transports: [any BandTransportProtocol]) { self.transports = transports }
    func make(_ link: any BandLink) -> any BandTransportProtocol {
        lock.lock(); defer { lock.unlock() }
        return transports.removeFirst()
    }
}

private actor SessionCentral: BandCentralProtocol {
    private var connectionCount = 0
    func scan() async -> AsyncThrowingStream<[BandCandidate], Error> { AsyncThrowingStream { $0.finish() } }
    func stopScan() async {}
    func connect(id: UUID) async throws -> any BandLink { connectionCount += 1; return UnusedLink() }
    func count() -> Int { connectionCount }
}

private final class UnusedLink: BandLink, @unchecked Sendable {
    let maximumWriteLength = 512
    func write(_ data: Data) async throws {}
    func notifications() async -> AsyncThrowingStream<Data, Error> { AsyncThrowingStream { $0.finish() } }
    func close() async {}
}

private actor SessionTransport: BandTransportProtocol {
    private let stream: AsyncThrowingStream<BandTransportMessage, Error>
    private let continuation: AsyncThrowingStream<BandTransportMessage, Error>.Continuation
    private var responses: [[BandTransportMessage]]
    private var isClosed = false
    init(responses: [[BandTransportMessage]]) {
        self.responses = responses
        var continuation: AsyncThrowingStream<BandTransportMessage, Error>.Continuation!
        stream = AsyncThrowingStream { continuation = $0 }
        self.continuation = continuation
    }
    func configure() async throws {}
    func send(channel: UInt8, opcode: UInt8, body: Data) async throws {
        if !responses.isEmpty { responses.removeFirst().forEach { continuation.yield($0) } }
    }
    func incoming() async -> AsyncThrowingStream<BandTransportMessage, Error> { stream }
    func close() async { isClosed = true; continuation.finish() }
    func closed() -> Bool { isClosed }
}
