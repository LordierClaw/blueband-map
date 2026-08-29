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
}

public actor InterconnectSession {
    public enum Error: Swift.Error, Equatable {
        case notReady
        case unexpectedPackage
        case fingerprintMismatch
        case identityMismatch
    }

    public typealias CommandSender = @Sendable (BandCommand) async throws -> Void
    public typealias IDGenerator = @Sendable () -> String

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
    private var deliveryTasks: [String: Task<Void, Never>] = [:]
    private var deliveryWaiters: [String: CheckedContinuation<String, Swift.Error>] = [:]
    private var earlyAcknowledgements: Set<String> = []

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
            guard let identity else { throw Error.notReady }
            guard messageIdentity == identity else { throw Error.identityMismatch }
            let envelope = try ApplicationEnvelope.decode(content, expecting: .ios)
            switch envelope.type {
            case .message:
                let ack = ApplicationEnvelope.acknowledgement(id: envelope.id, source: .ios)
                try await sendCommand(ThirdPartyAppCodec.phoneMessage(identity: identity, content: try ack.encoded()))
                if remember(envelope.id) { eventContinuation.yield(.received(envelope)) }
            case .ack:
                if let task = deliveryTasks.removeValue(forKey: envelope.id) {
                    task.cancel()
                    let waiter = deliveryWaiters.removeValue(forKey: envelope.id)
                    eventContinuation.yield(.acknowledged(envelope.id))
                    waiter?.resume(returning: envelope.id)
                } else if deliveryWaiters[envelope.id] != nil {
                    earlyAcknowledgements.insert(envelope.id)
                }
            }
        }
    }

    @discardableResult
    public func send(topic: String, body: [String: JSONValue]) async throws -> String {
        guard let identity else { throw Error.notReady }
        let envelope = ApplicationEnvelope.message(id: idGenerator(), source: .ios, topic: topic, body: body)
        try await sendCommand(ThirdPartyAppCodec.phoneMessage(identity: identity, content: try envelope.encoded()))
        eventContinuation.yield(.sent(envelope))
        let id = envelope.id
        startDeliveryTimeout(for: id)
        return id
    }

    @discardableResult
    public func sendAwaitingAcknowledgement(topic: String, body: [String: JSONValue]) async throws -> String {
        guard let identity else { throw Error.notReady }
        let envelope = ApplicationEnvelope.message(id: idGenerator(), source: .ios, topic: topic, body: body)
        let command = ThirdPartyAppCodec.phoneMessage(identity: identity, content: try envelope.encoded())
        let id = envelope.id
        return try await withCheckedThrowingContinuation { continuation in
            deliveryWaiters[id] = continuation
            Task { await transmitAwaited(command, envelope: envelope) }
        }
    }

    public func disconnect() async {
        let disconnectedIdentity = identity
        identity = nil
        deliveryTasks.values.forEach { $0.cancel() }
        deliveryTasks.removeAll()
        earlyAcknowledgements.removeAll()
        let waiters = Array(deliveryWaiters.values)
        deliveryWaiters.removeAll()
        waiters.forEach { $0.resume(throwing: InterconnectDeliveryError.disconnected) }
        recentIDs.removeAll()
        recentIDSet.removeAll()
        eventContinuation.yield(.disconnected)
        eventContinuation.finish()
        if let disconnectedIdentity {
            try? await sendCommand(ThirdPartyAppCodec.status(identity: disconnectedIdentity, connected: false))
        }
    }

    private func accept(_ requestedIdentity: ThirdPartyAppIdentity) async throws {
        guard requestedIdentity.packageName == expectedPackage else { throw Error.unexpectedPackage }
        if let trusted = try await trustedRPKStore.trustedRPKFingerprint() {
            guard SessionCrypto.constantTimeEqual(trusted, requestedIdentity.fingerprint) else {
                eventContinuation.yield(.trustRejected)
                throw Error.fingerprintMismatch
            }
        } else {
            try await trustedRPKStore.saveTrustedRPKFingerprint(requestedIdentity.fingerprint)
        }
        try await sendCommand(ThirdPartyAppCodec.status(identity: requestedIdentity, connected: true))
        identity = requestedIdentity
        eventContinuation.yield(.connected)
    }

    private func remember(_ id: String) -> Bool {
        guard recentIDSet.insert(id).inserted else { return false }
        recentIDs.append(id)
        if recentIDs.count > 64 { recentIDSet.remove(recentIDs.removeFirst()) }
        return true
    }

    private func transmitAwaited(_ command: BandCommand, envelope: ApplicationEnvelope) async {
        let id = envelope.id
        guard deliveryWaiters[id] != nil else { return }
        do {
            try await sendCommand(command)
        } catch {
            deliveryTasks.removeValue(forKey: id)?.cancel()
            earlyAcknowledgements.remove(id)
            guard let waiter = deliveryWaiters.removeValue(forKey: id) else { return }
            waiter.resume(throwing: error)
            eventContinuation.yield(.failed(id))
            return
        }
        guard deliveryWaiters[id] != nil else { return }
        eventContinuation.yield(.sent(envelope))
        if earlyAcknowledgements.remove(id) != nil {
            let waiter = deliveryWaiters.removeValue(forKey: id)
            eventContinuation.yield(.acknowledged(id))
            waiter?.resume(returning: id)
        } else {
            startDeliveryTimeout(for: id)
        }
    }

    private func startDeliveryTimeout(for id: String) {
        let clock = clock
        deliveryTasks[id]?.cancel()
        deliveryTasks[id] = Task { [weak self, clock] in
            do {
                try await clock.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                await self?.deliveryTimedOut(id)
            } catch {}
        }
    }

    private func deliveryTimedOut(_ id: String) {
        guard deliveryTasks.removeValue(forKey: id) != nil else { return }
        deliveryWaiters.removeValue(forKey: id)?.resume(
            throwing: InterconnectDeliveryError.timeout(id)
        )
        eventContinuation.yield(.failed(id))
    }
}
