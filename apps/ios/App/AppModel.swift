import Combine
import Foundation
import BlueBandCore
import BlueBandMapCore
import BlueBandProtocol

enum RPKState: Equatable, Sendable {
    case locked
    case waiting
    case ready
    case failed(String)
}

enum EchoDelivery: String, Equatable, Sendable {
    case sent
    case acknowledged
    case failed
    case received
}

struct EchoEntry: Identifiable, Equatable, Sendable {
    let id: String
    let source: ApplicationEnvelope.Source
    let text: String
    var delivery: EchoDelivery
}

protocol M1SessionSending: Sendable {
    func sendAwaitingAcknowledgement(topic: String, body: [String: JSONValue]) async throws
}

struct BandSessionM1Sender: M1SessionSending, Sendable {
    let session: BandSession

    func sendAwaitingAcknowledgement(topic: String, body: [String: JSONValue]) async throws {
        _ = try await session.sendAwaitingAcknowledgement(topic: topic, body: body)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var authKeyInput = ""
    @Published var tileMapKeyInput = ""
    @Published var serviceKeyInput = ""
    @Published var echoInput = "PING"
    @Published private(set) var hasSavedKey = false
    @Published private(set) var hasTileMapKey = false
    @Published private(set) var hasServiceKey = false
    @Published private(set) var candidates: [BandCandidate] = []
    @Published private(set) var rememberedBand: RememberedBand?
    @Published private(set) var sessionState: SessionState = .idle
    @Published private(set) var rpkState: RPKState = .locked
    @Published private(set) var snapshot = BandSnapshot()
    @Published private(set) var events: [EchoEntry] = []
    @Published private(set) var m1State: M1State = .idle
    @Published private(set) var errorMessage: String?

    private let keyStore: any AuthKeyStoreProtocol
    private let vietmapKeyStore: any VietmapKeyStoreProtocol
    private let bandStore: any RememberedBandStoreProtocol
    private let trustedRPKStore: any TrustedRPKStore
    private let central: any BandCentralProtocol
    private let session: BandSession
    private let staticMapProvider: any StaticMapProviding
    private let m1Session: any M1SessionSending
    private let scanDuration: Duration
    private var scanGeneration = 0
    private var eventTask: Task<Void, Never>?
    private var currentM1Attempt: UUID?
    private var pendingM1Asset: PendingM1Asset?

    private struct PendingM1Asset: Sendable {
        enum Phase: Sendable {
            case transferring(awaitingStep: Int)
            case waitingForBand
        }

        // The Band result has no run token; this token only rejects stale local continuations.
        let runToken: UUID
        let id: String
        let hashPrefix: String
        let byteCount: Int
        var phase: Phase
    }

    init(
        keyStore: any AuthKeyStoreProtocol,
        vietmapKeyStore: any VietmapKeyStoreProtocol,
        bandStore: any RememberedBandStoreProtocol,
        trustedRPKStore: any TrustedRPKStore,
        central: any BandCentralProtocol,
        session: BandSession,
        staticMapProvider: any StaticMapProviding,
        m1Session: any M1SessionSending,
        scanDuration: Duration = .seconds(15)
    ) {
        self.keyStore = keyStore
        self.vietmapKeyStore = vietmapKeyStore
        self.bandStore = bandStore
        self.trustedRPKStore = trustedRPKStore
        self.central = central
        self.session = session
        self.staticMapProvider = staticMapProvider
        self.m1Session = m1Session
        self.scanDuration = scanDuration
        rememberedBand = bandStore.load()
        do { hasSavedKey = try keyStore.load() != nil }
        catch { errorMessage = "Không đọc được AuthKey trong Keychain." }
        loadVietmapKeyHealth()
    }

    var pickerCandidates: [BandCandidate] {
        BandCandidateOrdering.order(candidates, remembered: rememberedBand)
    }

    func saveKey() {
        errorMessage = nil
        do {
            try keyStore.save(AuthKey(hex: authKeyInput))
            authKeyInput = ""
            hasSavedKey = true
        } catch is AuthKey.ValidationError {
            errorMessage = "AuthKey phải có đúng 32 ký tự hex. Giá trị không được ghi log."
        } catch {
            errorMessage = "Không lưu được AuthKey vào Keychain."
        }
    }

    func deleteKey() {
        errorMessage = nil
        do {
            try keyStore.delete()
            authKeyInput = ""
            hasSavedKey = false
        } catch { errorMessage = "Không xóa được AuthKey khỏi Keychain." }
    }

    func saveVietmapKey(_ kind: VietmapKeyKind) {
        errorMessage = nil
        do {
            switch kind {
            case .tileMap:
                try vietmapKeyStore.save(tileMapKeyInput, kind: .tileMap)
                tileMapKeyInput = ""
                hasTileMapKey = true
            case .service:
                try vietmapKeyStore.save(serviceKeyInput, kind: .service)
                serviceKeyInput = ""
                hasServiceKey = true
            }
        } catch {
            errorMessage = "Không lưu được cấu hình Vietmap vào Keychain."
        }
    }

    func deleteVietmapKey(_ kind: VietmapKeyKind) {
        errorMessage = nil
        do {
            try vietmapKeyStore.delete(kind)
            switch kind {
            case .tileMap:
                tileMapKeyInput = ""
                hasTileMapKey = false
            case .service:
                serviceKeyInput = ""
                hasServiceKey = false
            }
        } catch {
            errorMessage = "Không xóa được cấu hình Vietmap khỏi Keychain."
        }
    }

    func scan() async {
        guard sessionState == .idle else { return }
        errorMessage = nil
        candidates = []
        scanGeneration += 1
        let generation = scanGeneration
        sessionState = .scanning
        let timeout = Task { @MainActor [weak self, scanDuration] in
            do { try await Task.sleep(for: scanDuration) }
            catch { return }
            guard !Task.isCancelled else { return }
            await self?.stopScan(generation: generation)
        }

        await withTaskCancellationHandler {
            defer { timeout.cancel() }
            do {
                let stream = await central.scan()
                for try await batch in stream {
                    guard generation == scanGeneration, !Task.isCancelled else { break }
                    candidates = batch
                }
            } catch {
                if generation == scanGeneration, !Task.isCancelled {
                    errorMessage = safeMessage(for: error)
                }
            }

            if Task.isCancelled {
                await stopScan(generation: generation)
                return
            }

            if generation == scanGeneration, sessionState == .scanning {
                sessionState = .idle
            }
        } onCancel: {
            timeout.cancel()
            Task { @MainActor [weak self] in
                await self?.stopScan(generation: generation)
            }
        }
    }

    func stopScan(clear: Bool = false) async {
        await stopScan(generation: scanGeneration, clear: clear)
    }

    private func stopScan(generation: Int, clear: Bool = false) async {
        guard generation == scanGeneration else { return }
        scanGeneration += 1
        await central.stopScan()
        if clear { candidates = [] }
        if sessionState == .scanning { sessionState = .idle }
    }

    func connect(to candidate: BandCandidate) async {
        guard sessionState == .idle || sessionState == .scanning else { return }
        errorMessage = nil
        let key: AuthKey
        do {
            guard let loadedKey = try keyStore.load() else {
                errorMessage = "Hãy lưu AuthKey trước khi kết nối."
                return
            }
            key = loadedKey
        } catch {
            errorMessage = "Không đọc được AuthKey trong Keychain."
            return
        }

        if sessionState == .scanning {
            await stopScan()
        }

        do {
            sessionState = .connecting
            try await session.connect(candidate: candidate, authKey: key)
            sessionState = .readingDeviceProof
            snapshot = try await session.requestProofData()
            let remembered = RememberedBand(
                id: candidate.id,
                name: candidate.name,
                lastConnectedAt: Date()
            )
            bandStore.save(remembered)
            rememberedBand = remembered
            sessionState = .waitingForRpk
            rpkState = .waiting
            listenForEvents()
        } catch {
            await session.disconnect()
            sessionState = .idle
            rpkState = .locked
            errorMessage = safeMessage(for: error)
        }
    }

    func disconnect() async {
        guard sessionState != .idle else { return }
        sessionState = .disconnecting
        eventTask?.cancel()
        if !isM1Terminal {
            currentM1Attempt = nil
            failM1("TRANSFER_DISCONNECTED")
        }
        await session.disconnect()
        rpkState = .locked
        sessionState = .idle
    }

    func sendEcho() async {
        guard rpkState == .ready else { return }
        do {
            _ = try await session.send(topic: "system.echo", body: ["text": .string(echoInput)])
        } catch { errorMessage = "Không gửi được echo tới band." }
    }

    func startM1() async {
        guard isM1Terminal else { return }
        guard rpkState == .ready else {
            failM1("RPK_NOT_READY")
            return
        }

        let serviceKey: String
        do {
            guard let savedServiceKey = try vietmapKeyStore.load(.service) else {
                failM1("SERVICE_KEY_MISSING")
                return
            }
            serviceKey = savedServiceKey
        } catch {
            failM1("SERVICE_KEY_MISSING")
            return
        }

        let attempt = UUID()
        currentM1Attempt = attempt
        pendingM1Asset = nil
        m1State = .fetching

        let asset: MapAsset
        do {
            asset = try await staticMapProvider.fetch(M1Configuration.request, serviceKey: serviceKey)
        } catch {
            guard currentM1Attempt == attempt else { return }
            failM1(Task.isCancelled ? "TRANSFER_CANCELLED" : providerCode(for: error))
            return
        }
        guard currentM1Attempt == attempt else { return }
        guard !Task.isCancelled else {
            failM1("TRANSFER_CANCELLED")
            return
        }

        let steps: [MapTransferStep]
        do {
            steps = try MapAssetTransferPlan.make(asset: asset)
        } catch {
            failM1("ASSET_INVALID")
            return
        }

        let expected = PendingM1Asset(
            runToken: attempt,
            id: asset.id,
            hashPrefix: String(asset.sha256.prefix(8)),
            byteCount: asset.byteCount,
            phase: .transferring(awaitingStep: 0)
        )
        pendingM1Asset = expected
        m1State = .transferring(completed: 0, total: steps.count)
        do {
            for (index, step) in steps.enumerated() {
                guard currentM1Attempt == attempt,
                      var pending = pendingM1Asset,
                      pending.runToken == attempt else {
                    return
                }
                guard !Task.isCancelled else {
                    failM1("TRANSFER_CANCELLED")
                    return
                }
                pending.phase = .transferring(awaitingStep: index)
                pendingM1Asset = pending
                try await m1Session.sendAwaitingAcknowledgement(topic: step.topic, body: step.body)
                guard currentM1Attempt == attempt,
                      let current = pendingM1Asset,
                      current.runToken == attempt,
                      case let .transferring(awaitingStep) = current.phase,
                      awaitingStep == index,
                      case .transferring = m1State else {
                    return
                }
                guard !Task.isCancelled else {
                    failM1("TRANSFER_CANCELLED")
                    return
                }
                m1State = .transferring(completed: index + 1, total: steps.count)
            }
        } catch {
            guard currentM1Attempt == attempt else { return }
            failM1(Task.isCancelled ? "TRANSFER_CANCELLED" : transferCode(for: error))
            return
        }

        guard currentM1Attempt == attempt,
              var pending = pendingM1Asset,
              pending.runToken == attempt else {
            return
        }
        pending.phase = .waitingForBand
        pendingM1Asset = pending
        m1State = .waitingForBand(assetID: pending.id, hashPrefix: pending.hashPrefix)
    }

    func clearEvents() { events = [] }
    func forgetBand() { bandStore.forget(); rememberedBand = nil }

    func resetTrustedRPK() async {
        do {
            try await trustedRPKStore.resetTrustedRPKFingerprint()
            rpkState = sessionState == .waitingForRpk ? .waiting : .locked
        } catch { errorMessage = "Không reset được fingerprint RPK trong Keychain." }
    }

    private func listenForEvents() {
        eventTask?.cancel()
        eventTask = Task { [weak self, session] in
            for await event in await session.interconnectEvents() {
                guard !Task.isCancelled else { return }
                self?.consume(event)
            }
        }
    }

    private func loadVietmapKeyHealth() {
        do {
            hasTileMapKey = try vietmapKeyStore.load(.tileMap) != nil
        } catch {
            errorMessage = "Không đọc được cấu hình Vietmap trong Keychain."
        }
        do {
            hasServiceKey = try vietmapKeyStore.load(.service) != nil
        } catch {
            errorMessage = "Không đọc được cấu hình Vietmap trong Keychain."
        }
    }

    func consume(_ event: InterconnectEvent) {
        switch event {
        case .connected:
            rpkState = .ready
            sessionState = .applicationReady
        case .disconnected:
            rpkState = .locked
            if !isM1Terminal {
                currentM1Attempt = nil
                failM1("TRANSFER_DISCONNECTED")
            }
        case let .sent(envelope):
            append(envelope, delivery: .sent)
        case let .received(envelope):
            consumeM1Result(envelope)
            append(envelope, delivery: .received)
        case let .acknowledged(id):
            if let index = events.lastIndex(where: { $0.id == id }) { events[index].delivery = .acknowledged }
        case let .failed(id):
            if let index = events.lastIndex(where: { $0.id == id }) { events[index].delivery = .failed }
        case .trustRejected:
            rpkState = .failed("Fingerprint RPK đã thay đổi")
            errorMessage = "Fingerprint RPK đã thay đổi. Chỉ reset trust nếu bạn vừa cài lại RPK tin cậy."
        }
    }

    private var isM1Terminal: Bool {
        switch m1State {
        case .idle, .displayed, .failed: true
        case .fetching, .transferring, .waitingForBand: false
        }
    }

    private func failM1(_ code: String) {
        currentM1Attempt = nil
        pendingM1Asset = nil
        m1State = .failed(code: code)
    }

    private func providerCode(for error: Swift.Error) -> String {
        switch error {
        case VietmapStaticMapError.rateLimited:
            "PROVIDER_RATE_LIMITED"
        case VietmapStaticMapError.httpStatus:
            "PROVIDER_HTTP"
        case VietmapStaticMapError.wrongContentType:
            "PROVIDER_MIME"
        case is MapAsset.Error, is MapAssetTransferPlan.Error:
            "ASSET_INVALID"
        default:
            "PROVIDER_REQUEST"
        }
    }

    private func transferCode(for error: Swift.Error) -> String {
        switch error {
        case is CancellationError:
            "TRANSFER_CANCELLED"
        case InterconnectDeliveryError.timeout:
            "TRANSFER_TIMEOUT"
        case InterconnectDeliveryError.disconnected,
             BandSessionError.disconnected,
             BandSessionError.notConnected,
             InterconnectSession.Error.notReady:
            "TRANSFER_DISCONNECTED"
        default:
            "TRANSFER_FAILED"
        }
    }

    private func consumeM1Result(_ envelope: ApplicationEnvelope) {
        guard envelope.src == .band,
              envelope.type == .message,
              envelope.topic == "map.asset.result",
              let expected = pendingM1Asset,
              currentM1Attempt == expected.runToken,
              let body = envelope.body,
              case let .string(receivedAsset)? = body["asset"],
              receivedAsset == expected.id else {
            return
        }

        let isTransferring: Bool
        switch (m1State, expected.phase) {
        case (.transferring, .transferring):
            isTransferring = true
        case let (.waitingForBand(assetID, hashPrefix), .waitingForBand)
            where assetID == expected.id && hashPrefix == expected.hashPrefix:
            isTransferring = false
        default:
            return
        }

        guard case let .string(status)? = body["status"],
              case let .number(rawBytes)? = body["bytes"],
              rawBytes.isFinite,
              rawBytes.rounded(.towardZero) == rawBytes,
              rawBytes >= 0,
              rawBytes <= Double(MapAsset.maximumPNGBytes),
              case let .string(receivedPrefix)? = body["sha256Prefix"],
              isResultHashPrefix(receivedPrefix) else {
            return
        }

        if let rawCode = body["code"], case .string = rawCode {
            // The exact value is validated below for error results.
        } else if body["code"] != nil {
            return
        }

        switch status {
        case "ok":
            guard Int(rawBytes) == expected.byteCount,
                  receivedPrefix == expected.hashPrefix else {
                failM1("ASSET_RESULT_INVALID")
                return
            }
            guard !isTransferring else {
                failM1("ASSET_RESULT_INVALID")
                return
            }
            currentM1Attempt = nil
            pendingM1Asset = nil
            m1State = .displayed(assetID: expected.id, hashPrefix: expected.hashPrefix)
        case "error":
            guard Int(rawBytes) <= expected.byteCount,
                  receivedPrefix.isEmpty || receivedPrefix == expected.hashPrefix else {
                return
            }
            guard case let .string(code)? = body["code"], isAssetCode(code) else {
                failM1("ASSET_RESULT_INVALID")
                return
            }
            failM1(code)
        default:
            return
        }
    }

    private func isResultHashPrefix(_ value: String) -> Bool {
        value.isEmpty || isHashPrefix(value)
    }

    private func isHashPrefix(_ value: String) -> Bool {
        value.utf8.count == 8 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private func isAssetCode(_ value: String) -> Bool {
        guard value.hasPrefix("ASSET_") else { return false }
        let suffix = value.utf8.dropFirst(6)
        return (1...40).contains(suffix.count) && suffix.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || $0 == 95
        }
    }

    private func append(_ envelope: ApplicationEnvelope, delivery: EchoDelivery) {
        guard envelope.topic == "system.echo", case let .string(text)? = envelope.body?["text"] else { return }
        events.append(EchoEntry(id: envelope.id, source: envelope.src, text: text, delivery: delivery))
        if events.count > 40 { events.removeFirst(events.count - 40) }
    }

    private func safeMessage(for error: Swift.Error) -> String {
        switch error {
        case BandAuthenticationError.hmacMismatch: return "Xác thực thất bại. Hãy kiểm tra AuthKey."
        case BandAuthenticationError.timeout, BandSessionError.timeout: return "Band không phản hồi trong thời gian chờ."
        case BandBLEError.bluetoothUnavailable: return "Bluetooth chưa sẵn sàng hoặc chưa được cấp quyền."
        case BandBLEError.serviceMissing, BandBLEError.characteristicMissing: return "Thiết bị không có Xiaomi BLE V2 FE95/5E/5F."
        case InterconnectSession.Error.fingerprintMismatch: return "Fingerprint RPK đã thay đổi. Chỉ reset trust nếu bạn vừa cài lại RPK tin cậy."
        default: return "Kết nối thất bại. Hãy đóng Mi Fitness và thử lại."
        }
    }
}
