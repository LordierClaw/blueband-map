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

    func testEarlyAcknowledgementWaitsForSuccessfulTransmissionThenOrdersEvents() async throws {
        let sender = ControllableCommandSender()
        let clock = ImmediateRecordingClock()
        let session = InterconnectSession(
            expectedPackage: identity.packageName,
            trustedRPKStore: MemoryTrustStore(),
            clock: clock,
            idGenerator: { "i-early-success" },
            sendCommand: { command in try await sender.send(command) }
        )
        var events = await session.events().makeAsyncIterator()
        try await session.receive(.statusRequest(identity))
        _ = await events.next()

        let result = Task {
            try await session.sendAwaitingAcknowledgement(topic: "system.echo", body: [:])
        }
        let outgoing = await sender.waitForPhoneCommand()
        let envelope = try decodePhoneEnvelope(outgoing)
        let ack = ApplicationEnvelope.acknowledgement(id: envelope.id, source: .band)
        try await session.receive(.wearMessage(identity: identity, content: try ack.encoded()))

        await sender.releasePhone(with: .success(()))
        let returnedID = try await result.value
        await session.disconnect()

        var remainingEvents: [InterconnectEvent] = []
        while let event = await events.next() { remainingEvents.append(event) }
        let timeoutDuration = await clock.lastDuration()
        XCTAssertEqual(returnedID, "i-early-success")
        XCTAssertEqual(remainingEvents, [.sent(envelope), .acknowledged(envelope.id), .disconnected])
        XCTAssertNil(timeoutDuration)
    }

    func testEarlyAcknowledgementCannotOverrideOriginalSendFailure() async throws {
        let sender = ControllableCommandSender()
        let session = InterconnectSession(
            expectedPackage: identity.packageName,
            trustedRPKStore: MemoryTrustStore(),
            idGenerator: { "i-early-failure" },
            sendCommand: { command in try await sender.send(command) }
        )
        var events = await session.events().makeAsyncIterator()
        try await session.receive(.statusRequest(identity))
        _ = await events.next()

        let result = Task<Result<String, Swift.Error>, Never> {
            do {
                return .success(try await session.sendAwaitingAcknowledgement(topic: "system.echo", body: [:]))
            } catch {
                return .failure(error)
            }
        }
        let outgoing = await sender.waitForPhoneCommand()
        let envelope = try decodePhoneEnvelope(outgoing)
        let ack = ApplicationEnvelope.acknowledgement(id: envelope.id, source: .band)
        try await session.receive(.wearMessage(identity: identity, content: try ack.encoded()))

        await sender.releasePhone(with: .failure(.rejected))
        let outcome = await result.value
        await session.disconnect()

        guard case let .failure(error) = outcome else {
            return XCTFail("Expected original send failure")
        }
        var remainingEvents: [InterconnectEvent] = []
        while let event = await events.next() { remainingEvents.append(event) }
        XCTAssertEqual(error as? TestSendError, .rejected)
        XCTAssertEqual(remainingEvents, [.failed(envelope.id), .disconnected])
    }

    func testDisconnectInvalidatesAwaitedSendBeforeBlockedStatusTransmission() async throws {
        let sender = ControllableCommandSender(suspendDisconnectStatus: true)
        let session = InterconnectSession(
            expectedPackage: identity.packageName,
            trustedRPKStore: MemoryTrustStore(),
            idGenerator: { "i-disconnect-race" },
            sendCommand: { command in try await sender.send(command) }
        )
        var events = await session.events().makeAsyncIterator()
        try await session.receive(.statusRequest(identity))
        _ = await events.next()

        let result = Task<Result<String, Swift.Error>, Never> {
            do {
                return .success(try await session.sendAwaitingAcknowledgement(topic: "system.echo", body: [:]))
            } catch {
                return .failure(error)
            }
        }
        let outgoing = await sender.waitForPhoneCommand()
        let envelope = try decodePhoneEnvelope(outgoing)
        let disconnectTask = Task { await session.disconnect() }
        let statusCommand = await sender.waitForDisconnectStatusCommand()

        let lateAck = ApplicationEnvelope.acknowledgement(id: envelope.id, source: .band)
        do {
            try await session.receive(.wearMessage(identity: identity, content: try lateAck.encoded()))
            XCTFail("Expected disconnected session to reject ACK")
        } catch {
            XCTAssertEqual(error as? InterconnectSession.Error, .notReady)
        }
        let outcome = await result.value

        await sender.releasePhone(with: .success(()))
        await sender.releaseDisconnectStatus()
        await disconnectTask.value

        guard case let .failure(error) = outcome else {
            return XCTFail("Expected disconnected delivery")
        }
        var remainingEvents: [InterconnectEvent] = []
        while let event = await events.next() { remainingEvents.append(event) }
        XCTAssertEqual(error as? InterconnectDeliveryError, .disconnected)
        XCTAssertEqual(
            statusCommand,
            ThirdPartyAppCodec.status(identity: identity, connected: false)
        )
        XCTAssertEqual(remainingEvents, [.disconnected])
    }

    func testCancellationBeforeAwaitedSendRegistrationThrowsCancellationWithoutDeliveryEvents() async throws {
        let sender = ControllableCommandSender()
        let gate = ManualGate()
        let clock = ImmediateRecordingClock()
        let session = InterconnectSession(
            expectedPackage: identity.packageName,
            trustedRPKStore: MemoryTrustStore(),
            clock: clock,
            idGenerator: { "i-cancel-before" },
            sendCommand: { command in try await sender.send(command) }
        )
        var events = await session.events().makeAsyncIterator()
        try await session.receive(.statusRequest(identity))
        _ = await events.next()

        let completed = expectation(description: "cancelled send completes before transmission")
        let result = Task<Result<String, Swift.Error>, Never> {
            await gate.wait()
            defer { completed.fulfill() }
            do {
                return .success(try await session.sendAwaitingAcknowledgement(topic: "system.echo", body: [:]))
            } catch {
                return .failure(error)
            }
        }
        await gate.waitUntilBlocked()
        result.cancel()
        await gate.release()
        await fulfillment(of: [completed], timeout: 0.1)
        await sender.releasePhone(with: .success(()))
        let outcome = await result.value
        await session.disconnect()

        guard case let .failure(error) = outcome else {
            return XCTFail("Expected cancellation")
        }
        var remainingEvents: [InterconnectEvent] = []
        while let event = await events.next() { remainingEvents.append(event) }
        let phoneCount = await sender.phoneSendCount()
        let timeoutDuration = await clock.lastDuration()
        XCTAssertTrue(error is CancellationError)
        XCTAssertEqual(phoneCount, 0)
        XCTAssertNil(timeoutDuration)
        XCTAssertEqual(remainingEvents, [.disconnected])
    }

    func testCancellationWhileTransmitIsSuspendedRemovesDeliveryAndLateCompletionIsInert() async throws {
        let sender = ControllableCommandSender()
        let clock = ImmediateRecordingClock()
        let session = InterconnectSession(
            expectedPackage: identity.packageName,
            trustedRPKStore: MemoryTrustStore(),
            clock: clock,
            idGenerator: { "i-cancel-suspended" },
            sendCommand: { command in try await sender.send(command) }
        )
        var events = await session.events().makeAsyncIterator()
        try await session.receive(.statusRequest(identity))
        _ = await events.next()

        let completed = expectation(description: "cancelled suspended send completes promptly")
        let result = Task<Result<String, Swift.Error>, Never> {
            defer { completed.fulfill() }
            do {
                return .success(try await session.sendAwaitingAcknowledgement(topic: "system.echo", body: [:]))
            } catch {
                return .failure(error)
            }
        }
        let outgoing = await sender.waitForPhoneCommand()
        let envelope = try decodePhoneEnvelope(outgoing)
        result.cancel()
        await fulfillment(of: [completed], timeout: 0.1)
        await sender.releasePhone(with: .success(()))
        let outcome = await result.value

        let ack = ApplicationEnvelope.acknowledgement(id: envelope.id, source: .band)
        try await session.receive(.wearMessage(identity: identity, content: try ack.encoded()))
        await session.disconnect()

        guard case let .failure(error) = outcome else {
            return XCTFail("Expected cancellation")
        }
        var remainingEvents: [InterconnectEvent] = []
        while let event = await events.next() { remainingEvents.append(event) }
        let timeoutDuration = await clock.lastDuration()
        XCTAssertTrue(error is CancellationError)
        XCTAssertNil(timeoutDuration)
        XCTAssertEqual(remainingEvents, [.disconnected])
    }

    func testCancelledNonCooperativeTransmitDoesNotRetainSession() async throws {
        let sender = ControllableCommandSender()
        var session: InterconnectSession? = InterconnectSession(
            expectedPackage: identity.packageName,
            trustedRPKStore: MemoryTrustStore(),
            idGenerator: { "i-noncooperative-retention" },
            sendCommand: { command in try await sender.send(command) }
        )
        weak var weakSession = session
        try await session?.receive(.statusRequest(identity))

        var result: Task<Result<String, Swift.Error>, Never>? = Task { [session] in
            do {
                return .success(try await session!.sendAwaitingAcknowledgement(
                    topic: "system.echo",
                    body: [:]
                ))
            } catch {
                return .failure(error)
            }
        }
        _ = await sender.waitForPhoneCommand()
        result?.cancel()
        guard case let .failure(error) = await result?.value else {
            return XCTFail("Expected cancellation")
        }
        XCTAssertTrue(error is CancellationError)

        result = nil
        session = nil
        await Task.yield()
        XCTAssertNil(weakSession)

        await sender.releasePhone(with: .success(()))
    }

    func testBlockedLegacySendCannotBecomeSentAfterTerminalDisconnect() async throws {
        let sender = ControllableCommandSender()
        let clock = ImmediateRecordingClock()
        let session = InterconnectSession(
            expectedPackage: identity.packageName,
            trustedRPKStore: MemoryTrustStore(),
            clock: clock,
            idGenerator: { "i-legacy-terminal" },
            sendCommand: { command in try await sender.send(command) }
        )
        var events = await session.events().makeAsyncIterator()
        try await session.receive(.statusRequest(identity))
        _ = await events.next()

        let result = Task<Result<String, Swift.Error>, Never> {
            do {
                return .success(try await session.send(topic: "system.echo", body: [:]))
            } catch {
                return .failure(error)
            }
        }
        _ = await sender.waitForPhoneCommand()
        await session.disconnect()
        await sender.releasePhone(with: .success(()))
        let outcome = await result.value

        guard case let .failure(error) = outcome else {
            return XCTFail("Expected terminal send failure")
        }
        var remainingEvents: [InterconnectEvent] = []
        while let event = await events.next() { remainingEvents.append(event) }
        let timeoutDuration = await clock.lastDuration()
        XCTAssertEqual(error as? InterconnectDeliveryError, .disconnected)
        XCTAssertNil(timeoutDuration)
        XCTAssertEqual(remainingEvents, [.disconnected])
    }

    func testBlockedHandshakeCannotRestoreReadyStateAfterTerminalDisconnect() async throws {
        let sender = ControllableCommandSender(suspendConnectedStatus: true)
        let session = InterconnectSession(
            expectedPackage: identity.packageName,
            trustedRPKStore: MemoryTrustStore(),
            sendCommand: { command in try await sender.send(command) }
        )
        var events = await session.events().makeAsyncIterator()
        let accept = Task<Result<Void, Swift.Error>, Never> {
            do {
                try await session.receive(.statusRequest(identity))
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        _ = await sender.waitForConnectedStatusCommand()
        await session.disconnect()
        await sender.releaseConnectedStatus()
        let outcome = await accept.value

        guard case let .failure(error) = outcome else {
            return XCTFail("Expected terminal handshake failure")
        }
        var remainingEvents: [InterconnectEvent] = []
        while let event = await events.next() { remainingEvents.append(event) }
        XCTAssertEqual(error as? InterconnectSession.Error, .notReady)
        XCTAssertEqual(remainingEvents, [.disconnected])
    }

    func testAwaitedIdentifierCollisionRejectsSecondAndKeepsFirstCorrelated() async throws {
        let sender = ControllableCommandSender()
        let session = InterconnectSession(
            expectedPackage: identity.packageName,
            trustedRPKStore: MemoryTrustStore(),
            idGenerator: { "i-collision" },
            sendCommand: { command in try await sender.send(command) }
        )
        var events = await session.events().makeAsyncIterator()
        try await session.receive(.statusRequest(identity))
        _ = await events.next()

        let first = Task {
            try await session.sendAwaitingAcknowledgement(topic: "first", body: [:])
        }
        let outgoing = await sender.waitForPhoneCommand()
        let envelope = try decodePhoneEnvelope(outgoing)
        do {
            _ = try await session.sendAwaitingAcknowledgement(topic: "second", body: [:])
            XCTFail("Expected identifier collision")
        } catch {
            XCTAssertEqual(error as? InterconnectDeliveryError, .identifierCollision("i-collision"))
        }
        let phoneCount = await sender.phoneSendCount()
        XCTAssertEqual(phoneCount, 1)

        await sender.releasePhone(with: .success(()))
        let sent = await events.next()
        XCTAssertEqual(sent, .sent(envelope))
        let ack = ApplicationEnvelope.acknowledgement(id: envelope.id, source: .band)
        try await session.receive(.wearMessage(identity: identity, content: try ack.encoded()))
        let returnedID = try await first.value
        let acknowledged = await events.next()
        XCTAssertEqual(returnedID, "i-collision")
        XCTAssertEqual(acknowledged, .acknowledged("i-collision"))
    }

    func testBlockedLegacyIdentifierReservationRejectsAwaitedCollisionAndKeepsLegacyCorrelated() async throws {
        let sender = ControllableCommandSender()
        let session = InterconnectSession(
            expectedPackage: identity.packageName,
            trustedRPKStore: MemoryTrustStore(),
            idGenerator: { "i-cross-collision" },
            sendCommand: { command in try await sender.send(command) }
        )
        var events = await session.events().makeAsyncIterator()
        try await session.receive(.statusRequest(identity))
        _ = await events.next()

        let legacy = Task {
            try await session.send(topic: "legacy", body: [:])
        }
        let outgoing = await sender.waitForPhoneCommand()
        let envelope = try decodePhoneEnvelope(outgoing)
        do {
            _ = try await session.sendAwaitingAcknowledgement(topic: "awaited", body: [:])
            XCTFail("Expected identifier collision")
        } catch {
            XCTAssertEqual(error as? InterconnectDeliveryError, .identifierCollision("i-cross-collision"))
        }
        let phoneCount = await sender.phoneSendCount()
        XCTAssertEqual(phoneCount, 1)

        await sender.releasePhone(with: .success(()))
        let returnedID = try await legacy.value
        let sent = await events.next()
        XCTAssertEqual(returnedID, "i-cross-collision")
        XCTAssertEqual(sent, .sent(envelope))
        let ack = ApplicationEnvelope.acknowledgement(id: envelope.id, source: .band)
        try await session.receive(.wearMessage(identity: identity, content: try ack.encoded()))
        let acknowledged = await events.next()
        XCTAssertEqual(acknowledged, .acknowledged("i-cross-collision"))
    }

    func testCompletedAwaitedIdentifierCannotBeReusedByLegacySend() async throws {
        let recorder = CommandRecorder()
        let session = makeSession(recorder: recorder, trust: MemoryTrustStore())
        var events = await session.events().makeAsyncIterator()
        try await session.receive(.statusRequest(identity))
        _ = await events.next()

        let first = Task {
            try await session.sendAwaitingAcknowledgement(topic: "first", body: [:])
        }
        let commands = await recorder.commands(countAtLeast: 2)
        let envelope = try decodePhoneEnvelope(commands[1])
        _ = await events.next()
        let ack = ApplicationEnvelope.acknowledgement(id: envelope.id, source: .band)
        try await session.receive(.wearMessage(identity: identity, content: try ack.encoded()))
        let firstID = try await first.value
        XCTAssertEqual(firstID, "i-test")
        _ = await events.next()

        do {
            _ = try await session.send(topic: "second", body: [:])
            XCTFail("Expected identifier collision")
        } catch {
            XCTAssertEqual(error as? InterconnectDeliveryError, .identifierCollision("i-test"))
        }
        let commandCount = await recorder.commands().count
        XCTAssertEqual(commandCount, 2)
    }

    func testCompletedLegacyIdentifierCannotBeReusedByAwaitedSend() async throws {
        let recorder = CommandRecorder()
        let session = makeSession(recorder: recorder, trust: MemoryTrustStore())
        var events = await session.events().makeAsyncIterator()
        try await session.receive(.statusRequest(identity))
        _ = await events.next()

        let id = try await session.send(topic: "first", body: [:])
        _ = await events.next()
        let ack = ApplicationEnvelope.acknowledgement(id: id, source: .band)
        try await session.receive(.wearMessage(identity: identity, content: try ack.encoded()))
        _ = await events.next()

        do {
            _ = try await session.sendAwaitingAcknowledgement(topic: "second", body: [:])
            XCTFail("Expected identifier collision")
        } catch {
            XCTAssertEqual(error as? InterconnectDeliveryError, .identifierCollision("i-test"))
        }
        let commandCount = await recorder.commands().count
        XCTAssertEqual(commandCount, 2)
    }

    func testCompletedOutgoingIdentifierTombstonesEvictOldestAtBound() async throws {
        let recorder = CommandRecorder()
        let generatedIDs = (0...64).map { "i-terminal-\($0)" } + ["i-terminal-0"]
        let ids = LockedIDSequence(generatedIDs)
        let session = makeSession(
            recorder: recorder,
            trust: MemoryTrustStore(),
            idGenerator: { ids.next() }
        )
        var events = await session.events().makeAsyncIterator()
        try await session.receive(.statusRequest(identity))
        _ = await events.next()

        for index in 0...64 {
            let id = try await session.send(topic: "terminal-\(index)", body: [:])
            XCTAssertEqual(id, "i-terminal-\(index)")
            _ = await events.next()
            let ack = ApplicationEnvelope.acknowledgement(id: id, source: .band)
            try await session.receive(.wearMessage(identity: identity, content: try ack.encoded()))
            let acknowledged = await events.next()
            XCTAssertEqual(acknowledged, .acknowledged(id))
        }

        let reused = try await session.send(topic: "oldest-reused", body: [:])
        XCTAssertEqual(reused, "i-terminal-0")
        let sent = await events.next()
        guard case let .sent(envelope) = sent else {
            return XCTFail("Expected reused oldest ID to transmit")
        }
        XCTAssertEqual(envelope.id, reused)
    }

    func testPendingOutgoingIdentifierNeverEvictsUnderTerminalChurn() async throws {
        let recorder = CommandRecorder()
        let generatedIDs = ["i-held"] + (0...64).map { "i-churn-\($0)" } + ["i-held"]
        let ids = LockedIDSequence(generatedIDs)
        let session = makeSession(
            recorder: recorder,
            trust: MemoryTrustStore(),
            idGenerator: { ids.next() }
        )
        var events = await session.events().makeAsyncIterator()
        try await session.receive(.statusRequest(identity))
        _ = await events.next()

        let heldID = try await session.send(topic: "held", body: [:])
        XCTAssertEqual(heldID, "i-held")
        _ = await events.next()
        for index in 0...64 {
            let id = try await session.send(topic: "churn-\(index)", body: [:])
            _ = await events.next()
            let ack = ApplicationEnvelope.acknowledgement(id: id, source: .band)
            try await session.receive(.wearMessage(identity: identity, content: try ack.encoded()))
            _ = await events.next()
        }

        do {
            _ = try await session.send(topic: "held-collision", body: [:])
            XCTFail("Expected pending identifier collision")
        } catch {
            XCTAssertEqual(error as? InterconnectDeliveryError, .identifierCollision("i-held"))
        }
        let commandCount = await recorder.commands().count
        XCTAssertEqual(commandCount, 67)
    }

    func testLateDuplicateAcknowledgementCannotAcknowledgeNewerDistinctDelivery() async throws {
        let recorder = CommandRecorder()
        let ids = LockedIDSequence(["i-old", "i-new"])
        let session = makeSession(
            recorder: recorder,
            trust: MemoryTrustStore(),
            idGenerator: { ids.next() }
        )
        var events = await session.events().makeAsyncIterator()
        try await session.receive(.statusRequest(identity))
        _ = await events.next()

        let oldResult = Task {
            try await session.sendAwaitingAcknowledgement(topic: "old", body: [:])
        }
        _ = await recorder.commands(countAtLeast: 2)
        _ = await events.next()
        let oldAck = ApplicationEnvelope.acknowledgement(id: "i-old", source: .band)
        try await session.receive(.wearMessage(identity: identity, content: try oldAck.encoded()))
        let oldID = try await oldResult.value
        XCTAssertEqual(oldID, "i-old")
        _ = await events.next()

        let newResult = Task {
            try await session.sendAwaitingAcknowledgement(topic: "new", body: [:])
        }
        _ = await recorder.commands(countAtLeast: 3)
        let newSent = await events.next()
        try await session.receive(.wearMessage(identity: identity, content: try oldAck.encoded()))
        let newAck = ApplicationEnvelope.acknowledgement(id: "i-new", source: .band)
        try await session.receive(.wearMessage(identity: identity, content: try newAck.encoded()))

        let newID = try await newResult.value
        XCTAssertEqual(newID, "i-new")
        guard case let .sent(newEnvelope) = newSent else {
            return XCTFail("Expected newer sent event")
        }
        XCTAssertEqual(newEnvelope.id, "i-new")
        let acknowledged = await events.next()
        XCTAssertEqual(acknowledged, .acknowledged("i-new"))
    }

    func testDisconnectDuringBlockedInboundAcknowledgementDoesNotReceiveMessage() async throws {
        let sender = ControllableCommandSender()
        let session = InterconnectSession(
            expectedPackage: identity.packageName,
            trustedRPKStore: MemoryTrustStore(),
            sendCommand: { command in try await sender.send(command) }
        )
        var events = await session.events().makeAsyncIterator()
        try await session.receive(.statusRequest(identity))
        _ = await events.next()
        let message = ApplicationEnvelope.message(
            id: "b-terminal",
            source: .band,
            topic: "system.echo",
            body: [:]
        )
        let packet = ThirdPartyAppPacket.wearMessage(
            identity: identity,
            content: try message.encoded()
        )

        let receive = Task<Result<Void, Swift.Error>, Never> {
            do {
                try await session.receive(packet)
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        _ = await sender.waitForPhoneCommand()
        await session.disconnect()
        await sender.releasePhone(with: .success(()))
        let outcome = await receive.value

        guard case let .failure(error) = outcome else {
            return XCTFail("Expected terminal inbound receive failure")
        }
        var remainingEvents: [InterconnectEvent] = []
        while let event = await events.next() { remainingEvents.append(event) }
        XCTAssertEqual(error as? InterconnectSession.Error, .notReady)
        XCTAssertEqual(remainingEvents, [.disconnected])
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

private actor ControllableCommandSender {
    private let suspendConnectedStatus: Bool
    private let suspendDisconnectStatus: Bool
    private var statusCount = 0
    private var phoneCount = 0
    private var phoneCommand: BandCommand?
    private var connectedStatusCommand: BandCommand?
    private var disconnectStatusCommand: BandCommand?
    private var phoneContinuation: CheckedContinuation<Void, Swift.Error>?
    private var connectedStatusContinuation: CheckedContinuation<Void, Never>?
    private var disconnectStatusContinuation: CheckedContinuation<Void, Never>?
    private var phoneWaiters: [CheckedContinuation<BandCommand, Never>] = []
    private var connectedStatusWaiters: [CheckedContinuation<BandCommand, Never>] = []
    private var disconnectStatusWaiters: [CheckedContinuation<BandCommand, Never>] = []

    init(suspendConnectedStatus: Bool = false, suspendDisconnectStatus: Bool = false) {
        self.suspendConnectedStatus = suspendConnectedStatus
        self.suspendDisconnectStatus = suspendDisconnectStatus
    }

    func send(_ command: BandCommand) async throws {
        if command.subtype == 7 {
            statusCount += 1
            if suspendConnectedStatus, statusCount == 1 {
                connectedStatusCommand = command
                connectedStatusWaiters.forEach { $0.resume(returning: command) }
                connectedStatusWaiters.removeAll()
                await withCheckedContinuation { continuation in
                    connectedStatusContinuation = continuation
                }
                return
            }
            guard suspendDisconnectStatus, statusCount > 1 else { return }
            disconnectStatusCommand = command
            disconnectStatusWaiters.forEach { $0.resume(returning: command) }
            disconnectStatusWaiters.removeAll()
            await withCheckedContinuation { continuation in
                disconnectStatusContinuation = continuation
            }
            return
        }
        guard command.subtype == 8 else { return }
        phoneCount += 1
        guard phoneCount == 1 else { throw TestSendError.rejected }
        phoneCommand = command
        try await withCheckedThrowingContinuation { continuation in
            phoneContinuation = continuation
            phoneWaiters.forEach { $0.resume(returning: command) }
            phoneWaiters.removeAll()
        }
    }

    func waitForPhoneCommand() async -> BandCommand {
        if let phoneCommand { return phoneCommand }
        return await withCheckedContinuation { phoneWaiters.append($0) }
    }

    func waitForDisconnectStatusCommand() async -> BandCommand {
        if let disconnectStatusCommand { return disconnectStatusCommand }
        return await withCheckedContinuation { disconnectStatusWaiters.append($0) }
    }

    func waitForConnectedStatusCommand() async -> BandCommand {
        if let connectedStatusCommand { return connectedStatusCommand }
        return await withCheckedContinuation { connectedStatusWaiters.append($0) }
    }

    func phoneSendCount() -> Int { phoneCount }

    func releasePhone(with result: Result<Void, TestSendError>) {
        guard let continuation = phoneContinuation else { return }
        phoneContinuation = nil
        switch result {
        case .success: continuation.resume()
        case let .failure(error): continuation.resume(throwing: error)
        }
    }

    func releaseDisconnectStatus() {
        disconnectStatusContinuation?.resume()
        disconnectStatusContinuation = nil
    }

    func releaseConnectedStatus() {
        connectedStatusContinuation?.resume()
        connectedStatusContinuation = nil
    }
}

private actor ManualGate {
    private var waiter: CheckedContinuation<Void, Never>?
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            waiter = continuation
            blockedWaiters.forEach { $0.resume() }
            blockedWaiters.removeAll()
        }
    }

    func waitUntilBlocked() async {
        if waiter != nil { return }
        await withCheckedContinuation { blockedWaiters.append($0) }
    }

    func release() {
        waiter?.resume()
        waiter = nil
    }
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
