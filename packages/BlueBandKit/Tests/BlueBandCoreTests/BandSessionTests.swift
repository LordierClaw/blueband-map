import CryptoSwift
import Foundation
import XCTest
import BlueBandCrypto
@testable import BlueBandProtocol
@testable import BlueBandCore

final class BandSessionTests: XCTestCase {
    private let authKey = try! AuthKey(bytes: Data((0x00..<0x10).map(UInt8.init)))
    private let phoneNonce = Data((0x20..<0x30).map(UInt8.init))
    private let watchNonce = Data((0x30..<0x40).map(UInt8.init))
    private let identity = ThirdPartyAppIdentity(
        packageName: "dev.lordierclaw.bluebandmap.band",
        fingerprint: Data([0x10, 0x20, 0x30])
    )

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

    func testNormalIncomingEndTerminatesPendingAwaitedSendAndClearsBandSession() async throws {
        try await assertIncomingTermination(throwing: nil)
    }

    func testThrowingIncomingEndTerminatesPendingAwaitedSendAndClearsBandSession() async throws {
        try await assertIncomingTermination(throwing: SessionStreamError.failed)
    }

    private func assertIncomingTermination(throwing streamError: Swift.Error?) async throws {
        let transport = try readyTransport(suspendSendNumber: 7)
        let session = makeSession(central: SessionCentral(), factory: TransportFactory([transport]))
        try await session.connect(candidate: BandCandidate(id: UUID(), name: "Band 10", rssi: -50), authKey: authKey)
        _ = try await session.requestProofData()
        var events = await session.interconnectEvents().makeAsyncIterator()
        await transport.yield(BandTransportMessage(
            channel: 1,
            opcode: 1,
            body: ThirdPartyAppCodec.statusRequestForTesting(identity).encode()
        ))
        await transport.waitForSendCount(6)
        let connected = await events.next()
        XCTAssertEqual(connected, .connected)

        let completed = expectation(description: "physical stream termination resumes pending send")
        let result = Task<Result<String, Swift.Error>, Never> {
            defer { completed.fulfill() }
            do {
                return .success(try await session.sendAwaitingAcknowledgement(topic: "system.echo", body: [:]))
            } catch {
                return .failure(error)
            }
        }
        await transport.waitForSendCount(7)
        if let streamError {
            await transport.finishIncoming(throwing: streamError)
        } else {
            await transport.finishIncoming()
        }
        await fulfillment(of: [completed], timeout: 0.1)

        let stateAfterEnd = await session.state()
        do {
            _ = try await session.send(topic: "after.end", body: [:])
            XCTFail("Expected not connected after physical stream termination")
        } catch {
            XCTAssertEqual(error as? BandSessionError, .notConnected)
        }

        await transport.releaseSuspendedSend()
        await session.disconnect()
        let outcome = await result.value
        guard case let .failure(error) = outcome else {
            return XCTFail("Expected disconnected pending delivery")
        }
        var remainingEvents: [InterconnectEvent] = []
        while let event = await events.next() { remainingEvents.append(event) }
        XCTAssertEqual(error as? InterconnectDeliveryError, .disconnected)
        XCTAssertEqual(stateAfterEnd, .idle)
        XCTAssertEqual(remainingEvents, [.disconnected])
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

    private func readyTransport(suspendSendNumber: Int) throws -> SessionTransport {
        let keys = try SessionCrypto.derive(authKey: authKey, phoneNonce: phoneNonce, watchNonce: watchNonce)
        let hmac = SessionCrypto.hmacSHA256(message: watchNonce + phoneNonce, key: keys.decryptKey)
        return SessionTransport(
            responses: [
                [watchMessage(hmac: hmac)],
                [BandTransportMessage(channel: 1, opcode: 1, body: Data([0x08, 0x01, 0x10, 0x1B]))],
                [BandTransportMessage(channel: 1, opcode: 1, body: Data([
                    0x08, 0x02, 0x10, 0x02, 0x22, 0x12, 0x1A, 0x10,
                    0x0A, 0x02, 0x53, 0x4E, 0x12, 0x03, 0x31, 0x2E, 0x30,
                    0x18, 0x63, 0x22, 0x03, 0x4D, 0x31, 0x30
                ]))],
                [],
                [BandTransportMessage(channel: 1, opcode: 1, body: Data([
                    0x08, 0x02, 0x10, 0x01, 0x22, 0x08,
                    0x12, 0x06, 0x0A, 0x04, 0x08, 0x57, 0x10, 0x02
                ]))]
            ],
            suspendSendNumber: suspendSendNumber
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
    private let suspendSendNumber: Int?
    private var sendCount = 0
    private var sendCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var suspendedSend: CheckedContinuation<Void, Never>?
    private var isClosed = false
    init(responses: [[BandTransportMessage]], suspendSendNumber: Int? = nil) {
        self.responses = responses
        self.suspendSendNumber = suspendSendNumber
        var continuation: AsyncThrowingStream<BandTransportMessage, Error>.Continuation!
        stream = AsyncThrowingStream { continuation = $0 }
        self.continuation = continuation
    }
    func configure() async throws {}
    func send(channel: UInt8, opcode: UInt8, body: Data) async throws {
        sendCount += 1
        let readyWaiters = sendCountWaiters.filter { sendCount >= $0.0 }
        sendCountWaiters.removeAll { sendCount >= $0.0 }
        readyWaiters.forEach { $0.1.resume() }
        if !responses.isEmpty { responses.removeFirst().forEach { continuation.yield($0) } }
        if sendCount == suspendSendNumber {
            await withCheckedContinuation { suspendedSend = $0 }
        }
    }
    func incoming() async -> AsyncThrowingStream<BandTransportMessage, Error> { stream }
    func close() async { isClosed = true; continuation.finish() }
    func closed() -> Bool { isClosed }
    func yield(_ message: BandTransportMessage) { continuation.yield(message) }
    func finishIncoming(throwing error: Swift.Error? = nil) {
        if let error { continuation.finish(throwing: error) }
        else { continuation.finish() }
    }
    func waitForSendCount(_ count: Int) async {
        if sendCount >= count { return }
        await withCheckedContinuation { sendCountWaiters.append((count, $0)) }
    }
    func releaseSuspendedSend() {
        suspendedSend?.resume()
        suspendedSend = nil
    }
}

private enum SessionStreamError: Swift.Error {
    case failed
}

private extension ThirdPartyAppCodec {
    static func statusRequestForTesting(_ identity: ThirdPartyAppIdentity) -> BandCommand {
        var basicInfo = ProtoWriter()
        basicInfo.putString(field: 1, value: identity.packageName)
        basicInfo.putBytes(field: 2, value: identity.fingerprint)
        var thirdPartyApp = ProtoWriter()
        thirdPartyApp.putBytes(field: 5, value: basicInfo.data)
        return BandCommand(type: 20, subtype: 6, bodyField: 22, body: thirdPartyApp.data)
    }
}
