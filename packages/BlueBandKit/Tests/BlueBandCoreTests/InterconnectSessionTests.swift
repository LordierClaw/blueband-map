import Foundation
import XCTest
import BlueBandProtocol
@testable import BlueBandCore

final class InterconnectSessionTests: XCTestCase {
    private let identity = ThirdPartyAppIdentity(
        packageName: "dev.lordierclaw.bluebandmap.band",
        fingerprint: Data([0x10, 0x20, 0x30])
    )

    func testFirstUseEnrollsAndSubsequentMismatchIsRejected() async throws {
        let recorder = CommandRecorder()
        let trust = MemoryTrustStore()
        let session = makeSession(recorder: recorder, trust: trust)
        try await session.receive(.statusRequest(identity))
        let enrolled = await trust.value()
        XCTAssertEqual(enrolled, identity.fingerprint)

        let changed = ThirdPartyAppIdentity(packageName: identity.packageName, fingerprint: Data([9]))
        do {
            try await session.receive(.statusRequest(changed))
            XCTFail("Expected fingerprint mismatch")
        } catch {
            XCTAssertEqual(error as? InterconnectSession.Error, .fingerprintMismatch)
        }
        let firstCommandCount = await recorder.commands().count
        XCTAssertEqual(firstCommandCount, 1)

        try await trust.resetTrustedRPKFingerprint()
        let replacement = makeSession(recorder: recorder, trust: trust)
        try await replacement.receive(.statusRequest(changed))
        let replaced = await trust.value()
        XCTAssertEqual(replaced, Data([9]))
    }

    func testWrongPackageNeverEnrollsOrReplies() async {
        let recorder = CommandRecorder()
        let trust = MemoryTrustStore()
        let session = makeSession(recorder: recorder, trust: trust)
        let wrong = ThirdPartyAppIdentity(packageName: "other.app", fingerprint: Data([1]))
        do {
            try await session.receive(.statusRequest(wrong))
            XCTFail("Expected package rejection")
        } catch {
            XCTAssertEqual(error as? InterconnectSession.Error, .unexpectedPackage)
        }
        let stored = await trust.value()
        let commandCount = await recorder.commands().count
        XCTAssertNil(stored)
        XCTAssertEqual(commandCount, 0)
    }

    func testMessageIsAcknowledgedAndDuplicateEmitsOnlyOnce() async throws {
        let recorder = CommandRecorder()
        let session = makeSession(recorder: recorder, trust: MemoryTrustStore())
        var events = await session.events().makeAsyncIterator()
        try await session.receive(.statusRequest(identity))
        _ = await events.next()
        let message = ApplicationEnvelope.message(
            id: "b-7", source: .band, topic: "system.echo", body: ["text": .string("PING")]
        )
        let packet = ThirdPartyAppPacket.wearMessage(identity: identity, content: try message.encoded())
        try await session.receive(packet)
        try await session.receive(packet)

        let receivedEvent = await events.next()
        let commandCount = await recorder.commands().count
        XCTAssertEqual(receivedEvent, .received(message))
        XCTAssertEqual(commandCount, 3)
    }

    func testOutgoingRequiresHandshakeAndAckCorrelates() async throws {
        let recorder = CommandRecorder()
        let session = makeSession(recorder: recorder, trust: MemoryTrustStore())
        do {
            _ = try await session.send(topic: "system.echo", body: ["text": .string("PING")])
            XCTFail("Expected not ready")
        } catch {
            XCTAssertEqual(error as? InterconnectSession.Error, .notReady)
        }
        var events = await session.events().makeAsyncIterator()
        try await session.receive(.statusRequest(identity))
        _ = await events.next()
        let id = try await session.send(topic: "system.echo", body: ["text": .string("PING")])
        let sent = await events.next()
        guard case .sent = sent else { return XCTFail("Expected sent event") }
        let ack = ApplicationEnvelope.acknowledgement(id: id, source: .band)
        try await session.receive(.wearMessage(identity: identity, content: try ack.encoded()))
        let ackEvent = await events.next()
        XCTAssertEqual(ackEvent, .acknowledged(id))
    }

    func testDeliveryFailsAfterClockReceivesFiveSecondsWithoutRetry() async throws {
        let recorder = CommandRecorder()
        let clock = ImmediateRecordingClock()
        let session = makeSession(recorder: recorder, trust: MemoryTrustStore(), clock: clock)
        var events = await session.events().makeAsyncIterator()
        try await session.receive(.statusRequest(identity))
        _ = await events.next()
        let id = try await session.send(topic: "system.echo", body: ["text": .string("PING")])
        _ = await events.next()
        let failedEvent = await events.next()
        let duration = await clock.lastDuration()
        let commandCount = await recorder.commands().count
        XCTAssertEqual(failedEvent, .failed(id))
        XCTAssertEqual(duration, .seconds(5))
        XCTAssertEqual(commandCount, 2)
    }

    private func makeSession(
        recorder: CommandRecorder,
        trust: MemoryTrustStore,
        clock: any BlueBandClock = ContinuousBlueBandClock()
    ) -> InterconnectSession {
        InterconnectSession(
            expectedPackage: "dev.lordierclaw.bluebandmap.band",
            trustedRPKStore: trust,
            clock: clock,
            idGenerator: { "i-test" },
            sendCommand: { command in await recorder.append(command) }
        )
    }
}

private actor MemoryTrustStore: TrustedRPKStore {
    private var fingerprint: Data?
    func trustedRPKFingerprint() async throws -> Data? { fingerprint }
    func saveTrustedRPKFingerprint(_ value: Data) async throws { fingerprint = value }
    func resetTrustedRPKFingerprint() async throws { fingerprint = nil }
    func value() -> Data? { fingerprint }
}

private actor CommandRecorder {
    private var values: [BandCommand] = []
    func append(_ command: BandCommand) { values.append(command) }
    func commands() -> [BandCommand] { values }
}

private actor ImmediateRecordingClock: BlueBandClock {
    private var duration: Duration?
    func sleep(for duration: Duration) async throws { self.duration = duration }
    func lastDuration() -> Duration? { duration }
}
