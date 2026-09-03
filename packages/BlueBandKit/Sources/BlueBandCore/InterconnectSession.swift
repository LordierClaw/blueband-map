import Foundation
import BlueBandCrypto
import BlueBandProtocol

public enum InterconnectEvent: Equatable, Sendable {
    case connected
    case disconnected
    case sent(ApplicationEnvelope)
    case received(ApplicationEnvelope)
    case acknowledged(String)
    case failed(String)
    case trustRejected
}

public enum InterconnectDeliveryError: Swift.Error, Equatable, Sendable {
    case timeout(String)
    case disconnected
    case identifierCollision(String)
}

public actor InterconnectSession {
    private static let maximumCompletedOutgoingIDs = 64

    public enum Error: Swift.Error, Equatable {
        case notReady
        case unexpectedPackage
        case fingerprintMismatch
        case identityMismatch
    }

    public typealias CommandSender = @Sendable (BandCommand) async throws -> Void
    public typealias IDGenerator = @Sendable () -> String

    private struct PendingDelivery {
        let token: UUID
        let generation: UInt64
        let retryCommand: BandCommand?
        let retryEnvelope: ApplicationEnvelope?
        var waiter: CheckedContinuation<String, Swift.Error>?
        var transmitTask: Task<Void, Never>?
        var timeoutTask: Task<Void, Never>?
        var retryCount = 0
        var earlyAcknowledged = false
    }

    private let expectedPackage: String
    private let trustedRPKStore: any TrustedRPKStore
    private let clock: any BlueBandClock
    private let idGenerator: IDGenerator
    private let sendCommand: CommandSender
    private let eventStream: AsyncStream<InterconnectEvent>
    private let eventContinuation: AsyncStream<InterconnectEvent>.Continuation
    private var identity: ThirdPartyAppIdentity?
    private var recentIDs: [String] = []
    private var recentIDSet: Set<String> = []
    private var completedOutgoingIDs: [String] = []
    private var completedOutgoingIDSet: Set<String> = []
    private var pendingDeliveries: [String: PendingDelivery] = [:]
    private var generation: UInt64 = 0
    private var isTerminal = false

    public init(
        expectedPackage: String,
        trustedRPKStore: any TrustedRPKStore,
        clock: any BlueBandClock = ContinuousBlueBandClock(),
        idGenerator: @escaping IDGenerator = { "i-\(UUID().uuidString.prefix(12).lowercased())" },
        sendCommand: @escaping CommandSender
    ) {
        self.expectedPackage = expectedPackage
        self.trustedRPKStore = trustedRPKStore
        self.clock = clock
        self.idGenerator = idGenerator
        self.sendCommand = sendCommand
        var continuation: AsyncStream<InterconnectEvent>.Continuation!
        eventStream = AsyncStream(bufferingPolicy: .bufferingNewest(160)) { continuation = $0 }
        eventContinuation = continuation
    }

    public func events() -> AsyncStream<InterconnectEvent> { eventStream }

    public func receive(_ packet: ThirdPartyAppPacket) async throws {
        switch packet {
        case let .statusRequest(requestedIdentity):
            try await accept(requestedIdentity)
        case let .wearMessage(messageIdentity, content):
            guard !isTerminal, let identity else { throw Error.notReady }
            let currentGeneration = generation
            guard messageIdentity == identity else { throw Error.identityMismatch }
            let envelope = try ApplicationEnvelope.decode(content, expecting: .ios)
            switch envelope.type {
            case .message:
                let ack = ApplicationEnvelope.acknowledgement(id: envelope.id, source: .ios)
                try await sendCommand(ThirdPartyAppCodec.phoneMessage(identity: identity, content: try ack.encoded()))
                try ensureReceiveIsCurrent(currentGeneration, identity: identity)
                if remember(envelope.id) { eventContinuation.yield(.received(envelope)) }
            case .ack:
                guard var pending = pendingDeliveries[envelope.id] else { return }
                if pending.timeoutTask != nil || pending.retryCount > 0 {
                    _ = removeDelivery(id: envelope.id, token: pending.token)
                    pending.timeoutTask?.cancel()
                    pending.transmitTask?.cancel()
                    eventContinuation.yield(.acknowledged(envelope.id))
                    pending.waiter?.resume(returning: envelope.id)
                } else {
                    pending.earlyAcknowledged = true
                    pendingDeliveries[envelope.id] = pending
                }
            }
        }
    }

    @discardableResult
    public func send(topic: String, body: [String: JSONValue]) async throws -> String {
        guard !isTerminal, let identity else { throw Error.notReady }
        let currentGeneration = generation
        let envelope = ApplicationEnvelope.message(id: idGenerator(), source: .ios, topic: topic, body: body)
        let command = ThirdPartyAppCodec.phoneMessage(identity: identity, content: try envelope.encoded())
        let id = envelope.id
        let token = UUID()
        try reserve(id: id, token: token, generation: currentGeneration)
        do {
            try await sendCommand(command)
        } catch {
            guard isCurrent(id: id, token: token, generation: currentGeneration) else {
                throw InterconnectDeliveryError.disconnected
            }
            removeDelivery(id: id, token: token)
            throw error
        }
        guard isCurrent(id: id, token: token, generation: currentGeneration) else {
            throw InterconnectDeliveryError.disconnected
        }
        finishSuccessfulTransmission(id: id, token: token, envelope: envelope)
        return id
    }

    @discardableResult
    public func sendAwaitingAcknowledgement(topic: String, body: [String: JSONValue]) async throws -> String {
        guard !isTerminal, let identity else { throw Error.notReady }
        let currentGeneration = generation
        let envelope = ApplicationEnvelope.message(id: idGenerator(), source: .ios, topic: topic, body: body)
        let command = ThirdPartyAppCodec.phoneMessage(identity: identity, content: try envelope.encoded())
        let id = envelope.id
        let token = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                do {
                    try reserve(
                        id: id,
                        token: token,
                        generation: currentGeneration,
                        retryCommand: command,
                        retryEnvelope: envelope,
                        waiter: continuation
                    )
                    let transmitTask = Self.makeTransmitTask(
                        sender: sendCommand,
                        command: command,
                        envelope: envelope,
                        token: token,
                        generation: currentGeneration,
                        session: self
                    )
                    guard var pending = pendingDeliveries[id], pending.token == token else {
                        transmitTask.cancel()
                        return
                    }
                    pending.transmitTask = transmitTask
                    pendingDeliveries[id] = pending
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            Task { await self.cancelDelivery(id: id, token: token) }
        }
    }

    public func disconnect() async {
        guard !isTerminal else { return }
        let disconnectedIdentity = terminate()
        if let disconnectedIdentity {
            try? await sendCommand(ThirdPartyAppCodec.status(identity: disconnectedIdentity, connected: false))
        }
    }

    func transportDisconnected() {
        guard !isTerminal else { return }
        _ = terminate()
    }

    private func accept(_ requestedIdentity: ThirdPartyAppIdentity) async throws {
        guard !isTerminal else { throw Error.notReady }
        let currentGeneration = generation
        guard requestedIdentity.packageName == expectedPackage else { throw Error.unexpectedPackage }
        if let trusted = try await trustedRPKStore.trustedRPKFingerprint() {
            try ensureAcceptIsCurrent(currentGeneration)
            guard SessionCrypto.constantTimeEqual(trusted, requestedIdentity.fingerprint) else {
                eventContinuation.yield(.trustRejected)
                throw Error.fingerprintMismatch
            }
        } else {
            try ensureAcceptIsCurrent(currentGeneration)
            try await trustedRPKStore.saveTrustedRPKFingerprint(requestedIdentity.fingerprint)
            try ensureAcceptIsCurrent(currentGeneration)
        }
        try await sendCommand(ThirdPartyAppCodec.status(identity: requestedIdentity, connected: true))
        try ensureAcceptIsCurrent(currentGeneration)
        identity = requestedIdentity
        eventContinuation.yield(.connected)
    }

    private func remember(_ id: String) -> Bool {
        guard recentIDSet.insert(id).inserted else { return false }
        recentIDs.append(id)
        if recentIDs.count > 64 { recentIDSet.remove(recentIDs.removeFirst()) }
        return true
    }

    private nonisolated static func makeTransmitTask(
        sender: @escaping CommandSender,
        command: BandCommand,
        envelope: ApplicationEnvelope,
        token: UUID,
        generation: UInt64,
        session: InterconnectSession
    ) -> Task<Void, Never> {
        Task { [weak session, sender, command, envelope, token, generation] in
            do {
                try await sender(command)
                await session?.transmitAwaitedCompleted(
                    .success(()),
                    envelope: envelope,
                    token: token,
                    generation: generation
                )
            } catch {
                await session?.transmitAwaitedCompleted(
                    .failure(error),
                    envelope: envelope,
                    token: token,
                    generation: generation
                )
            }
        }
    }

    private func transmitAwaitedCompleted(
        _ result: Result<Void, Swift.Error>,
        envelope: ApplicationEnvelope,
        token: UUID,
        generation currentGeneration: UInt64
    ) {
        let id = envelope.id
        guard isCurrent(id: id, token: token, generation: currentGeneration) else { return }
        switch result {
        case let .failure(error):
            guard isCurrent(id: id, token: token, generation: currentGeneration),
                  let pending = removeDelivery(id: id, token: token) else { return }
            pending.timeoutTask?.cancel()
            pending.waiter?.resume(throwing: error)
            eventContinuation.yield(.failed(id))
        case .success:
            finishSuccessfulTransmission(id: id, token: token, envelope: envelope)
        }
    }

    private func startDeliveryTimeout(for id: String, token: UUID, generation: UInt64) {
        guard let pending = pendingDeliveries[id], pending.token == token else { return }
        let clock = clock
        let duration: Duration
        if pending.retryCommand == nil {
            duration = .seconds(5)
        } else {
            duration = pending.retryCount == 0 ? .seconds(1) : .seconds(3)
        }
        let timeoutTask = Task { [weak self, clock] in
            do {
                try await clock.sleep(for: duration)
                guard !Task.isCancelled else { return }
                await self?.deliveryTimedOut(id, token: token, generation: generation)
            } catch {}
        }
        guard var pending = pendingDeliveries[id], pending.token == token else {
            timeoutTask.cancel()
            return
        }
        pending.timeoutTask?.cancel()
        pending.timeoutTask = timeoutTask
        pendingDeliveries[id] = pending
    }

    private func deliveryTimedOut(_ id: String, token: UUID, generation: UInt64) {
        guard isCurrent(id: id, token: token, generation: generation),
              var pending = pendingDeliveries[id] else { return }
        if pending.retryCount == 0,
           let command = pending.retryCommand,
           let envelope = pending.retryEnvelope {
            pending.retryCount = 1
            pending.timeoutTask = nil
            let transmitTask = Self.makeTransmitTask(
                sender: sendCommand,
                command: command,
                envelope: envelope,
                token: token,
                generation: generation,
                session: self
            )
            pending.transmitTask = transmitTask
            pendingDeliveries[id] = pending
            return
        }
        guard let pending = removeDelivery(id: id, token: token) else { return }
        pending.waiter?.resume(throwing: InterconnectDeliveryError.timeout(id))
        eventContinuation.yield(.failed(id))
    }

    private func reserve(
        id: String,
        token: UUID,
        generation: UInt64,
        retryCommand: BandCommand? = nil,
        retryEnvelope: ApplicationEnvelope? = nil,
        waiter: CheckedContinuation<String, Swift.Error>? = nil
    ) throws {
        guard !isTerminal, self.generation == generation else {
            throw InterconnectDeliveryError.disconnected
        }
        guard pendingDeliveries[id] == nil, !completedOutgoingIDSet.contains(id) else {
            throw InterconnectDeliveryError.identifierCollision(id)
        }
        pendingDeliveries[id] = PendingDelivery(
            token: token,
            generation: generation,
            retryCommand: retryCommand,
            retryEnvelope: retryEnvelope,
            waiter: waiter
        )
    }

    private func finishSuccessfulTransmission(id: String, token: UUID, envelope: ApplicationEnvelope) {
        guard var pending = pendingDeliveries[id], pending.token == token,
              !isTerminal, pending.generation == generation else { return }
        pending.transmitTask = nil
        pendingDeliveries[id] = pending
        if pending.retryCount == 0 { eventContinuation.yield(.sent(envelope)) }
        if pending.earlyAcknowledged {
            _ = removeDelivery(id: id, token: token)
            pending.timeoutTask?.cancel()
            eventContinuation.yield(.acknowledged(id))
            pending.waiter?.resume(returning: id)
        } else {
            startDeliveryTimeout(for: id, token: token, generation: pending.generation)
        }
    }

    private func cancelDelivery(id: String, token: UUID) {
        guard let pending = removeDelivery(id: id, token: token) else { return }
        pending.transmitTask?.cancel()
        pending.timeoutTask?.cancel()
        pending.waiter?.resume(throwing: CancellationError())
    }

    @discardableResult
    private func removeDelivery(id: String, token: UUID) -> PendingDelivery? {
        guard let pending = pendingDeliveries[id], pending.token == token else { return nil }
        pendingDeliveries.removeValue(forKey: id)
        rememberCompletedOutgoingID(id)
        return pending
    }

    private func rememberCompletedOutgoingID(_ id: String) {
        guard completedOutgoingIDSet.insert(id).inserted else { return }
        completedOutgoingIDs.append(id)
        if completedOutgoingIDs.count > Self.maximumCompletedOutgoingIDs {
            completedOutgoingIDSet.remove(completedOutgoingIDs.removeFirst())
        }
    }

    private func isCurrent(id: String, token: UUID, generation: UInt64) -> Bool {
        guard !isTerminal, self.generation == generation,
              let pending = pendingDeliveries[id] else { return false }
        return pending.token == token && pending.generation == generation
    }

    private func ensureAcceptIsCurrent(_ generation: UInt64) throws {
        guard !isTerminal, self.generation == generation else { throw Error.notReady }
    }

    private func ensureReceiveIsCurrent(
        _ generation: UInt64,
        identity expectedIdentity: ThirdPartyAppIdentity
    ) throws {
        guard !isTerminal, self.generation == generation, identity == expectedIdentity else {
            throw Error.notReady
        }
    }

    private func terminate() -> ThirdPartyAppIdentity? {
        isTerminal = true
        generation &+= 1
        let disconnectedIdentity = identity
        identity = nil
        let deliveries = Array(pendingDeliveries.values)
        pendingDeliveries.removeAll()
        deliveries.forEach {
            $0.transmitTask?.cancel()
            $0.timeoutTask?.cancel()
            $0.waiter?.resume(throwing: InterconnectDeliveryError.disconnected)
        }
        recentIDs.removeAll()
        recentIDSet.removeAll()
        completedOutgoingIDs.removeAll()
        completedOutgoingIDSet.removeAll()
        eventContinuation.yield(.disconnected)
        eventContinuation.finish()
        return disconnectedIdentity
    }
}
