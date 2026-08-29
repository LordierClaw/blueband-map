import Foundation
import BlueBandCrypto
import BlueBandProtocol

public typealias BandTransportFactory = @Sendable (any BandLink) -> any BandTransportProtocol

public actor BandSession {
    private let central: any BandCentralProtocol
    private let authenticator: BandAuthenticator
    private let cipher: any AESBlockCipher
    private let trustedRPKStore: any TrustedRPKStore
    private let expectedPackage: String
    private let proofTimeout: Duration
    private let transportFactory: BandTransportFactory
    private var transport: (any BandTransportProtocol)?
    private var keys: SessionKeys?
    private var interconnect: InterconnectSession?
    private var receiverTask: Task<Void, Never>?
    private var currentState: SessionState = .idle

    public init(
        central: any BandCentralProtocol,
        authenticator: BandAuthenticator,
        cipher: any AESBlockCipher,
        trustedRPKStore: any TrustedRPKStore,
        expectedPackage: String = "dev.lordierclaw.bluebandmap.band",
        proofTimeout: Duration = .seconds(10),
        transportFactory: @escaping BandTransportFactory = { BandTransport(link: $0) }
    ) {
        self.central = central
        self.authenticator = authenticator
        self.cipher = cipher
        self.trustedRPKStore = trustedRPKStore
        self.expectedPackage = expectedPackage
        self.proofTimeout = proofTimeout
        self.transportFactory = transportFactory
    }

    public func state() -> SessionState { currentState }

    public func connect(candidate: BandCandidate, authKey: AuthKey) async throws {
        guard transport == nil else { throw BandSessionError.alreadyConnected }
        currentState = .connecting
        do {
            for attempt in 0..<2 {
                let link = try await central.connect(id: candidate.id)
                currentState = .configuringSpp
                let candidateTransport = transportFactory(link)
                do {
                    currentState = .authenticating
                    let result = try await authenticator.authenticate(authKey: authKey, transport: candidateTransport)
                    transport = candidateTransport
                    keys = result.keys
                    currentState = .readingDeviceProof
                    return
                } catch BandAuthenticationError.hmacMismatch where attempt == 0 {
                    continue
                }
            }
            throw BandAuthenticationError.hmacMismatch
        } catch {
            currentState = .idle
            throw error
        }
    }

    public func requestProofData() async throws -> BandSnapshot {
        guard let transport, let keys else { throw BandSessionError.notConnected }
        currentState = .readingDeviceProof
        do {
            let snapshot = try await withThrowingTaskGroup(of: BandSnapshot.self) { group in
                let cipher = cipher
                group.addTask { try await Self.readProofData(transport: transport, keys: keys, cipher: cipher) }
                group.addTask { [proofTimeout] in
                    try await Task.sleep(for: proofTimeout)
                    throw BandSessionError.timeout
                }
                guard let result = try await group.next() else { throw BandSessionError.disconnected }
                group.cancelAll()
                return result
            }
            startInterconnect(transport: transport, keys: keys)
            currentState = .waitingForRpk
            return snapshot
        } catch {
            await clearAndClose(transport)
            throw error
        }
    }

    public func interconnectEvents() async -> AsyncStream<InterconnectEvent> {
        guard let interconnect else { return AsyncStream { $0.finish() } }
        return await interconnect.events()
    }

    @discardableResult
    public func send(topic: String, body: [String: JSONValue]) async throws -> String {
        guard let interconnect else { throw BandSessionError.notConnected }
        return try await interconnect.send(topic: topic, body: body)
    }

    @discardableResult
    public func sendAwaitingAcknowledgement(topic: String, body: [String: JSONValue]) async throws -> String {
        guard let interconnect else { throw BandSessionError.notConnected }
        return try await interconnect.sendAwaitingAcknowledgement(topic: topic, body: body)
    }

    public func disconnect() async {
        currentState = .disconnecting
        receiverTask?.cancel()
        receiverTask = nil
        await interconnect?.disconnect()
        interconnect = nil
        let activeTransport = transport
        transport = nil
        keys = nil
        await activeTransport?.close()
        currentState = .idle
    }

    private func startInterconnect(transport: any BandTransportProtocol, keys: SessionKeys) {
        guard interconnect == nil else { return }
        let cipher = cipher
        let session = InterconnectSession(
            expectedPackage: expectedPackage,
            trustedRPKStore: trustedRPKStore
        ) { command in
            let encrypted = try SessionCrypto.cryptCTR(command.encode(), key: keys.encryptKey, cipher: cipher)
            try await transport.send(channel: 1, opcode: 2, body: encrypted)
        }
        interconnect = session
        receiverTask = Task { [weak self, transport, keys, session, cipher] in
            let incoming = await transport.incoming()
            do {
                for try await message in incoming {
                    guard !Task.isCancelled, message.channel == 1 else { continue }
                    let plaintext: Data
                    switch message.opcode {
                    case 1: plaintext = message.body
                    case 2: plaintext = try SessionCrypto.cryptCTR(message.body, key: keys.decryptKey, cipher: cipher)
                    default: continue
                    }
                    guard let command = try? BandCommand.decode(plaintext), command.type == 20,
                          let packet = try? ThirdPartyAppCodec.decode(command) else { continue }
                    do {
                        try await session.receive(packet)
                        if case .statusRequest = packet { await self?.markApplicationReady() }
                    } catch {
                        // Reject malformed, unexpected, or untrusted app packets without
                        // surrendering the authenticated Band transport.
                        continue
                    }
                }
            } catch {}
            guard !Task.isCancelled else { return }
            await session.transportDisconnected()
            await self?.receiverTerminated(session: session, transport: transport)
        }
    }

    private func markApplicationReady() { currentState = .applicationReady }

    private func receiverTerminated(
        session: InterconnectSession,
        transport activeTransport: any BandTransportProtocol
    ) async {
        guard interconnect === session else { return }
        receiverTask = nil
        interconnect = nil
        transport = nil
        keys = nil
        currentState = .idle
        await activeTransport.close()
    }

    private func clearAndClose(_ activeTransport: any BandTransportProtocol) async {
        receiverTask?.cancel()
        receiverTask = nil
        interconnect = nil
        transport = nil
        keys = nil
        currentState = .idle
        await activeTransport.close()
    }

    private static func readProofData(
        transport: any BandTransportProtocol,
        keys: SessionKeys,
        cipher: any AESBlockCipher
    ) async throws -> BandSnapshot {
        var iterator = await transport.incoming().makeAsyncIterator()
        for command in [BandCommands.deviceInfoRequest, BandCommands.deviceStateRequest, BandCommands.batteryRequest] {
            let encrypted = try SessionCrypto.cryptCTR(command.encode(), key: keys.encryptKey, cipher: cipher)
            try await transport.send(channel: 1, opcode: 2, body: encrypted)
        }
        var snapshot = BandSnapshot()
        var hasInfo = false
        var hasBattery = false
        while let message = try await iterator.next() {
            guard message.channel == 1 else { continue }
            let plaintext: Data
            switch message.opcode {
            case 1: plaintext = message.body
            case 2: plaintext = try SessionCrypto.cryptCTR(message.body, key: keys.decryptKey, cipher: cipher)
            default: continue
            }
            guard let command = try? BandCommand.decode(plaintext), command.type == 2 else { continue }
            if let status = command.status, status != 0 { throw BandSessionError.rejected(status: status) }
            switch command.subtype {
            case 1:
                let battery = try BandBattery.decode(command)
                snapshot.batteryLevel = battery.level
                snapshot.batteryState = battery.state
                hasBattery = true
            case 2:
                let info = try BandDeviceInfo.decode(command)
                snapshot.model = info.model
                snapshot.firmware = info.firmware
                hasInfo = true
            default: continue
            }
            if hasInfo && hasBattery { return snapshot }
        }
        throw BandSessionError.disconnected
    }
}
