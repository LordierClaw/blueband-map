import Combine
import Foundation
import BlueBandCore
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
    @Published private(set) var errorMessage: String?

    private let keyStore: any AuthKeyStoreProtocol
    private let vietmapKeyStore: any VietmapKeyStoreProtocol
    private let bandStore: any RememberedBandStoreProtocol
    private let trustedRPKStore: any TrustedRPKStore
    private let central: any BandCentralProtocol
    private let session: BandSession
    private let scanDuration: Duration
    private var scanGeneration = 0
    private var eventTask: Task<Void, Never>?

    init(
        keyStore: any AuthKeyStoreProtocol,
        vietmapKeyStore: any VietmapKeyStoreProtocol,
        bandStore: any RememberedBandStoreProtocol,
        trustedRPKStore: any TrustedRPKStore,
        central: any BandCentralProtocol,
        session: BandSession,
        scanDuration: Duration = .seconds(15)
    ) {
        self.keyStore = keyStore
        self.vietmapKeyStore = vietmapKeyStore
        self.bandStore = bandStore
        self.trustedRPKStore = trustedRPKStore
        self.central = central
        self.session = session
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
        let stream = await central.scan()
        let timeout = Task { [central, scanDuration] in
            try? await Task.sleep(for: scanDuration)
            guard !Task.isCancelled else { return }
            await central.stopScan()
        }
        defer { timeout.cancel() }
        do {
            for try await batch in stream where generation == scanGeneration {
                candidates = batch
            }
        } catch { errorMessage = safeMessage(for: error) }
        if sessionState == .scanning { sessionState = .idle }
    }

    func stopScan(clear: Bool = false) async {
        scanGeneration += 1
        await central.stopScan()
        if clear { candidates = [] }
        if sessionState == .scanning { sessionState = .idle }
    }

    func connect(to candidate: BandCandidate) async {
        guard sessionState == .idle || sessionState == .scanning else { return }
        errorMessage = nil
        do {
            guard let key = try keyStore.load() else {
                errorMessage = "Hãy lưu AuthKey trước khi kết nối."
                sessionState = .idle
                return
            }
            await central.stopScan()
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

    private func consume(_ event: InterconnectEvent) {
        switch event {
        case .connected:
            rpkState = .ready
            sessionState = .applicationReady
        case .disconnected:
            rpkState = .locked
        case let .sent(envelope):
            append(envelope, delivery: .sent)
        case let .received(envelope):
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
