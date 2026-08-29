import Foundation
import XCTest
@testable import BlueBandProtocol
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
        var events = await session.events().makeAsyncIterator()
        try await session.receive(.statusRequest(identity))
        _ = await events.next()
        let enrolled = await trust.value()
        XCTAssertEqual(enrolled, identity.fingerprint)

        let changed = ThirdPartyAppIdentity(packageName: identity.packageName, fingerprint: Data([9]))
        do {
            try await session.receive(.statusRequest(changed))
            XCTFail("Expected fingerprint mismatch")
        } catch {
            XCTAssertEqual(error as? InterconnectSession.Error, .fingerprintMismatch)
        }
        let rejectedEvent = await events.next()
        XCTAssertEqual(rejectedEvent, .trustRejected)
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

    func testAwaitedSendReturnsMatchingAcknowledgementAfterSentEventUsingExistingCodecPath() async throws {
        let recorder = CommandRecorder()
        let session = makeSession(recorder: recorder, trust: MemoryTrustStore())
        var events = await session.events().makeAsyncIterator()
        try await session.receive(.statusRequest(identity))
        let connected = await events.next()
        XCTAssertEqual(connected, .connected)

        let result = Task {
            try await session.sendAwaitingAcknowledgement(
                topic: "system.echo",
                body: ["text": JSONValue.string("PING")]
            )
        }
        let commands = await recorder.commands(countAtLeast: 2)
        let outgoing = commands[1]
        let envelope = try decodePhoneEnvelope(outgoing)
        let expectedEnvelope = ApplicationEnvelope.message(
            id: "i-test",
            source: .ios,
            topic: "system.echo",
            body: ["text": .string("PING")]
        )
        XCTAssertEqual(envelope, expectedEnvelope)
        XCTAssertEqual(
            outgoing,
            ThirdPartyAppCodec.phoneMessage(identity: identity, content: try expectedEnvelope.encoded())
        )
        let sent = await events.next()
        XCTAssertEqual(sent, .sent(expectedEnvelope))

        let ack = ApplicationEnvelope.acknowledgement(id: envelope.id, source: .band)
        try await session.receive(.wearMessage(identity: identity, content: try ack.encoded()))

        let acknowledgedID = try await result.value
        let acknowledged = await events.next()
        XCTAssertEqual(acknowledgedID, "i-test")
        XCTAssertEqual(acknowledged, .acknowledged("i-test"))
    }

    func testAwaitedSendTimesOutOnceWithoutRetry() async throws {
        let recorder = CommandRecorder()
        let clock = ImmediateRecordingClock()
        let session = makeSession(recorder: recorder, trust: MemoryTrustStore(), clock: clock)
        var events = await session.events().makeAsyncIterator()
        try await session.receive(.statusRequest(identity))
        let connected = await events.next()
        XCTAssertEqual(connected, .connected)

        do {
            _ = try await session.sendAwaitingAcknowledgement(
                topic: "system.echo",
                body: ["text": JSONValue.string("PING")]
            )
            XCTFail("Expected delivery timeout")
        } catch {
            XCTAssertEqual(error as? InterconnectDeliveryError, .timeout("i-test"))
        }

        let commands = await recorder.commands()
        let envelope = try decodePhoneEnvelope(commands[1])
        let sent = await events.next()
        let failed = await events.next()
        let duration = await clock.lastDuration()
        XCTAssertEqual(sent, .sent(envelope))
        XCTAssertEqual(failed, .failed("i-test"))
        XCTAssertEqual(duration, .seconds(5))
        XCTAssertEqual(commands.count, 2)

        await session.disconnect()
        let disconnected = await events.next()
        let finished = await events.next()
        XCTAssertEqual(disconnected, .disconnected)
        XCTAssertNil(finished)
    }

    func testDisconnectResumesPendingAwaitedSendExactlyOnce() async throws {
        let recorder = CommandRecorder()
        let session = makeSession(recorder: recorder, trust: MemoryTrustStore())
        var events = await session.events().makeAsyncIterator()
        try await session.receive(.statusRequest(identity))
        let connected = await events.next()
        XCTAssertEqual(connected, .connected)

        let result = Task<Result<String, Swift.Error>, Never> {
            do {
                return .success(try await session.sendAwaitingAcknowledgement(
                    topic: "system.echo",
                    body: ["text": JSONValue.string("PING")]
                ))
            } catch {
                return .failure(error)
            }
        }
        let commands = await recorder.commands(countAtLeast: 2)
        let envelope = try decodePhoneEnvelope(commands[1])
        let sent = await events.next()
        XCTAssertEqual(sent, .sent(envelope))

        await session.disconnect()

        guard case let .failure(error) = await result.value else {
            return XCTFail("Expected disconnected error")
        }
        XCTAssertEqual(error as? InterconnectDeliveryError, .disconnected)
        let disconnected = await events.next()
        let finished = await events.next()
        XCTAssertEqual(disconnected, .disconnected)
        XCTAssertNil(finished)
    }

    func testSendCommandFailureResumesAwaitedSendWithOriginalErrorAndFailsOnce() async throws {
        let recorder = FailingCommandRecorder()
        let session = InterconnectSession(
            expectedPackage: identity.packageName,
            trustedRPKStore: MemoryTrustStore(),
            idGenerator: { "i-test" },
            sendCommand: { command in try await recorder.send(command) }
        )
        var events = await session.events().makeAsyncIterator()
        try await session.receive(.statusRequest(identity))
        let connected = await events.next()
        XCTAssertEqual(connected, .connected)

        do {
            _ = try await session.sendAwaitingAcknowledgement(
                topic: "system.echo",
                body: ["text": JSONValue.string("PING")]
            )
            XCTFail("Expected original send error")
        } catch {
            XCTAssertEqual(error as? TestSendError, .rejected)
        }

        let failed = await events.next()
        let attemptCount = await recorder.attemptCount()
        XCTAssertEqual(failed, .failed("i-test"))
        XCTAssertEqual(attemptCount, 2)
        await session.disconnect()
        let disconnected = await events.next()
        let finished = await events.next()
        XCTAssertEqual(disconnected, .disconnected)
        XCTAssertNil(finished)
    }

    func testDifferentAwaitedIDsCorrelateIndependently() async throws {
        let recorder = CommandRecorder()
        let ids = LockedIDSequence(["i-first", "i-second"])
        let session = makeSession(
            recorder: recorder,
            trust: MemoryTrustStore(),
            idGenerator: { ids.next() }
        )
        var events = await session.events().makeAsyncIterator()
        try await session.receive(.statusRequest(identity))
        _ = await events.next()

        let firstResult = Task {
            try await session.sendAwaitingAcknowledgement(topic: "first", body: [:])
        }
        let firstCommands = await recorder.commands(countAtLeast: 2)
        let firstEnvelope = try decodePhoneEnvelope(firstCommands[1])
        let firstSent = await events.next()
        XCTAssertEqual(firstEnvelope.id, "i-first")
        XCTAssertEqual(firstSent, .sent(firstEnvelope))

        let secondResult = Task {
            try await session.sendAwaitingAcknowledgement(topic: "second", body: [:])
        }
        let secondCommands = await recorder.commands(countAtLeast: 3)
        let secondEnvelope = try decodePhoneEnvelope(secondCommands[2])
        let secondSent = await events.next()
        XCTAssertEqual(secondEnvelope.id, "i-second")
        XCTAssertEqual(secondSent, .sent(secondEnvelope))

        let secondAck = ApplicationEnvelope.acknowledgement(id: secondEnvelope.id, source: .band)
        try await session.receive(.wearMessage(identity: identity, content: try secondAck.encoded()))
        let secondID = try await secondResult.value
        let secondAcknowledged = await events.next()
        XCTAssertEqual(secondID, "i-second")
        XCTAssertEqual(secondAcknowledged, .acknowledged("i-second"))

        let firstAck = ApplicationEnvelope.acknowledgement(id: firstEnvelope.id, source: .band)
        try await session.receive(.wearMessage(identity: identity, content: try firstAck.encoded()))
        let firstID = try await firstResult.value
        let firstAcknowledged = await events.next()
        XCTAssertEqual(firstID, "i-first")
        XCTAssertEqual(firstAcknowledged, .acknowledged("i-first"))
    }

    private func makeSession(
        recorder: CommandRecorder,
        trust: MemoryTrustStore,
        clock: any BlueBandClock = ContinuousBlueBandClock(),
        idGenerator: @escaping InterconnectSession.IDGenerator = { "i-test" }
    ) -> InterconnectSession {
        InterconnectSession(
            expectedPackage: "dev.lordierclaw.bluebandmap.band",
            trustedRPKStore: trust,
            clock: clock,
            idGenerator: idGenerator,
            sendCommand: { command in await recorder.append(command) }
        )
    }

    private func decodePhoneEnvelope(_ command: BandCommand) throws -> ApplicationEnvelope {
        guard command.type == 20, command.subtype == 8, command.bodyField == 22,
              let commandBody = command.body else {
            throw ThirdPartyAppCodec.Error.unexpectedCommand
        }
        let thirdPartyFields = try ProtoReader(data: commandBody).allFields()
        guard let rawMessage = thirdPartyFields.firstBytes(field: 9) else {
            throw ThirdPartyAppCodec.Error.missingField
        }
        let messageFields = try ProtoReader(data: rawMessage).allFields()
        guard let content = messageFields.firstBytes(field: 2) else {
            throw ThirdPartyAppCodec.Error.missingField
        }
        return try ApplicationEnvelope.decode(content, expecting: .band)
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
    private var waiters: [(Int, CheckedContinuation<[BandCommand], Never>)] = []

    func append(_ command: BandCommand) {
        values.append(command)
        let ready = waiters.filter { values.count >= $0.0 }
        waiters.removeAll { values.count >= $0.0 }
        ready.forEach { $0.1.resume(returning: values) }
    }

    func commands() -> [BandCommand] { values }

    func commands(countAtLeast count: Int) async -> [BandCommand] {
        if values.count >= count { return values }
        return await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }
}

private actor ImmediateRecordingClock: BlueBandClock {
    private var duration: Duration?
    func sleep(for duration: Duration) async throws { self.duration = duration }
    func lastDuration() -> Duration? { duration }
}

private enum TestSendError: Swift.Error, Equatable {
    case rejected
}

private actor FailingCommandRecorder {
    private var attempts = 0

    func send(_ command: BandCommand) throws {
        attempts += 1
        if attempts > 1 { throw TestSendError.rejected }
    }

    func attemptCount() -> Int { attempts }
}

private final class LockedIDSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String]

    init(_ values: [String]) {
        self.values = values
    }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        return values.removeFirst()
    }
}
