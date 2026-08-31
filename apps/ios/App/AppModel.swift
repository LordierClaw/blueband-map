import Combine
import CoreLocation
import Foundation
import BlueBandCore
import BlueBandMapCore
import BlueBandProtocol

enum RPKState: Equatable, Sendable { case locked, waiting, ready, failed(String) }
enum EchoDelivery: String, Equatable, Sendable { case sent, acknowledged, failed, received }
enum LiveNavigationState: Equatable, Sendable {
    case idle, waitingForGPS, routing, transferring, navigating, gpsLow, limitedMap, rerouting, arrived
    case failed(String)
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
    @Published var destinationLatitudeInput: String
    @Published var destinationLongitudeInput: String
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
    @Published private(set) var navigationState: LiveNavigationState = .idle
    @Published private(set) var navigationManeuver: NavigationManeuver = .straight
    @Published private(set) var navigationDistanceMeters = 0
    @Published private(set) var navigationStreet = ""
    @Published private(set) var routePreviewPNG: Data?
    @Published private(set) var errorMessage: String?

    private let keyStore: any AuthKeyStoreProtocol
    private let vietmapKeyStore: any VietmapKeyStoreProtocol
    private let bandStore: any RememberedBandStoreProtocol
    private let trustedRPKStore: any TrustedRPKStore
    private let central: any BandCentralProtocol
    private let session: BandSession
    private let routeClient: VietmapRouteClient
    private let assetFactory: RouteCardAssetFactory
    private let locationClient: ForegroundLocationClient
    private let renderCoordinator: RouteCardRenderCoordinator
    private let updateClock: any BlueBandClock
    private let defaults: UserDefaults
    private let scanDuration: Duration
    private var scanGeneration = 0
    private var eventTask: Task<Void, Never>?
    private var navigationTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var updateCoalescer = NavigationUpdateCoalescer()
    private var updateSequence = 0
    private var activeSceneID: String?
    private var activeAnchorIndex = 0

    init(
        keyStore: any AuthKeyStoreProtocol,
        vietmapKeyStore: any VietmapKeyStoreProtocol,
        bandStore: any RememberedBandStoreProtocol,
        trustedRPKStore: any TrustedRPKStore,
        central: any BandCentralProtocol,
        session: BandSession,
        routeClient: VietmapRouteClient,
        assetFactory: RouteCardAssetFactory,
        locationClient: ForegroundLocationClient,
        routeCardSession: (any RouteCardSessionSending)? = nil,
        updateClock: any BlueBandClock = ContinuousBlueBandClock(),
        defaults: UserDefaults = .standard,
        scanDuration: Duration = .seconds(15)
    ) {
        self.keyStore = keyStore
        self.vietmapKeyStore = vietmapKeyStore
        self.bandStore = bandStore
        self.trustedRPKStore = trustedRPKStore
        self.central = central
        self.session = session
        self.routeClient = routeClient
        self.assetFactory = assetFactory
        self.locationClient = locationClient
        self.updateClock = updateClock
        self.defaults = defaults
        self.scanDuration = scanDuration
        self.renderCoordinator = RouteCardRenderCoordinator(session: routeCardSession ?? BandSessionRouteCardSender(session: session))
        destinationLatitudeInput = defaults.string(forKey: "destinationLatitude") ?? ""
        destinationLongitudeInput = defaults.string(forKey: "destinationLongitude") ?? ""
        rememberedBand = bandStore.load()
        do { hasSavedKey = try keyStore.load() != nil }
        catch { errorMessage = "Không đọc được AuthKey trong Keychain." }
        loadVietmapKeyHealth()
    }

    var pickerCandidates: [BandCandidate] { BandCandidateOrdering.order(candidates, remembered: rememberedBand) }

    func saveKey() {
        errorMessage = nil
        do {
            try keyStore.save(AuthKey(hex: authKeyInput))
            authKeyInput = ""
            hasSavedKey = true
        } catch is AuthKey.ValidationError {
            errorMessage = "AuthKey phải có đúng 32 ký tự hex. Giá trị không được ghi log."
        } catch { errorMessage = "Không lưu được AuthKey vào Keychain." }
    }

    func deleteKey() {
        do { try keyStore.delete(); authKeyInput = ""; hasSavedKey = false }
        catch { errorMessage = "Không xóa được AuthKey khỏi Keychain." }
    }

    func saveVietmapKey(_ kind: VietmapKeyKind) {
        errorMessage = nil
        do {
            let value = kind == .tileMap ? tileMapKeyInput : serviceKeyInput
            try vietmapKeyStore.save(value, kind: kind)
            if kind == .tileMap { tileMapKeyInput = ""; hasTileMapKey = true }
            else { serviceKeyInput = ""; hasServiceKey = true }
        } catch { errorMessage = "Không lưu được cấu hình Vietmap vào Keychain." }
    }

    func deleteVietmapKey(_ kind: VietmapKeyKind) {
        do {
            try vietmapKeyStore.delete(kind)
            if kind == .tileMap { tileMapKeyInput = ""; hasTileMapKey = false }
            else { serviceKeyInput = ""; hasServiceKey = false }
        } catch { errorMessage = "Không xóa được cấu hình Vietmap khỏi Keychain." }
    }

    func saveDestination() {
        guard destination != nil else {
            errorMessage = "Tọa độ đích không hợp lệ."
            return
        }
        defaults.set(destinationLatitudeInput, forKey: "destinationLatitude")
        defaults.set(destinationLongitudeInput, forKey: "destinationLongitude")
        errorMessage = nil
    }

    func scan() async {
        guard sessionState == .idle else { return }
        errorMessage = nil
        candidates = []
        scanGeneration += 1
        let generation = scanGeneration
        sessionState = .scanning
        let timeout = Task { @MainActor [weak self, scanDuration] in
            do { try await Task.sleep(for: scanDuration) } catch { return }
            await self?.stopScan(generation: generation)
        }
        await withTaskCancellationHandler {
            defer { timeout.cancel() }
            do {
                for try await batch in await central.scan() {
                    guard generation == scanGeneration, !Task.isCancelled else { break }
                    candidates = batch
                }
            } catch where !Task.isCancelled { errorMessage = safeMessage(for: error) }
            if Task.isCancelled { await stopScan(generation: generation); return }
            if generation == scanGeneration, sessionState == .scanning { sessionState = .idle }
        } onCancel: {
            timeout.cancel()
            Task { @MainActor [weak self] in await self?.stopScan(generation: generation) }
        }
    }

    func stopScan(clear: Bool = false) async { await stopScan(generation: scanGeneration, clear: clear) }

    private func stopScan(generation: Int, clear: Bool = false) async {
        guard generation == scanGeneration else { return }
        scanGeneration += 1
        await central.stopScan()
        if clear { candidates = [] }
        if sessionState == .scanning { sessionState = .idle }
    }

    func connect(to candidate: BandCandidate) async {
        guard sessionState == .idle || sessionState == .scanning else { return }
        let key: AuthKey
        do {
            guard let value = try keyStore.load() else { errorMessage = "Hãy lưu AuthKey trước khi kết nối."; return }
            key = value
        } catch { errorMessage = "Không đọc được AuthKey trong Keychain."; return }
        if sessionState == .scanning { await stopScan() }
        do {
            sessionState = .connecting
            try await session.connect(candidate: candidate, authKey: key)
            sessionState = .readingDeviceProof
            snapshot = try await session.requestProofData()
            let band = RememberedBand(id: candidate.id, name: candidate.name, lastConnectedAt: Date())
            bandStore.save(band)
            rememberedBand = band
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
        stopNavigation()
        sessionState = .disconnecting
        eventTask?.cancel()
        renderCoordinator.disconnected()
        await session.disconnect()
        rpkState = .locked
        sessionState = .idle
    }

    func startNavigation() {
        guard navigationTask == nil, rpkState == .ready else {
            navigationState = .failed("RPK_NOT_READY")
            return
        }
        guard let destination, let serviceKey = loadVietmapKey(.service) else {
            navigationState = .failed("CONFIG_MISSING")
            return
        }
        saveDestination()
        navigationTask = Task { @MainActor [weak self] in
            await self?.runNavigation(
                destination: destination,
                serviceKey: serviceKey,
                tileMapKey: self?.loadVietmapKey(.tileMap) ?? ""
            )
        }
    }

    func stopNavigation() {
        navigationTask?.cancel()
        navigationTask = nil
        updateTask?.cancel()
        updateTask = nil
        updateCoalescer.reset()
        locationClient.stop()
        activeSceneID = nil
        routePreviewPNG = nil
        navigationState = .idle
    }

    private func runNavigation(destination: GeoPoint, serviceKey: String, tileMapKey: String) async {
        defer { navigationTask = nil }
        navigationState = .waitingForGPS
        do {
            var iterator = locationClient.locations().makeAsyncIterator()
            var first: CLLocation?
            while let location = try await iterator.next() {
                guard !Task.isCancelled else { return }
                if location.horizontalAccuracy <= 25 { first = location; break }
                navigationState = .gpsLow
            }
            guard !Task.isCancelled else { return }
            guard let first else { throw ForegroundLocationClient.Error.unavailable }
            var route = try await makeRoute(from: first, to: destination, serviceKey: serviceKey)
            var tracker = RouteProgressTracker()
            var progress = tracker.update(route: route, location: first.geoPoint, horizontalAccuracyMeters: first.horizontalAccuracy)
            var limitedMap = try await publish(route: route, progressIndex: progress.pointIndex, tileMapKey: tileMapKey)
            var lastReroute = Date.distantPast
            var lastGoodLocation = first.geoPoint
            sendNavigationUpdate(route: route, progress: progress, location: first.geoPoint, status: limitedMap ? .limitedMap : .navigating)

            while let location = try await iterator.next() {
                guard !Task.isCancelled else { return }
                progress = tracker.update(route: route, location: location.geoPoint, horizontalAccuracyMeters: location.horizontalAccuracy)
                let goodFix = location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 25
                if goodFix { lastGoodLocation = location.geoPoint }
                let displayedLocation = goodFix ? location.geoPoint : lastGoodLocation
                if goodFix && Self.meters(location.geoPoint, destination) <= 25 {
                    navigationState = .arrived
                    sendNavigationUpdate(route: route, progress: progress, location: displayedLocation, status: .arrived)
                    return
                }
                if progress.shouldReroute, Date().timeIntervalSince(lastReroute) >= 15 {
                    navigationState = .rerouting
                    sendNavigationUpdate(route: route, progress: progress, location: displayedLocation, status: .rerouting)
                    route = try await makeRoute(from: location, to: destination, serviceKey: serviceKey)
                    tracker = RouteProgressTracker()
                    progress = tracker.update(route: route, location: location.geoPoint, horizontalAccuracyMeters: location.horizontalAccuracy)
                    limitedMap = try await publish(route: route, progressIndex: progress.pointIndex, tileMapKey: tileMapKey)
                    lastReroute = Date()
                }
                var status: NavigationStatus = progress.status == .gpsLow ? .gpsLow : (limitedMap ? .limitedMap : .navigating)
                if status != .gpsLow,
                   RouteCardBuilder.marker(route: route, anchorProgressIndex: activeAnchorIndex, location: location.geoPoint) == nil {
                    limitedMap = try await publish(route: route, progressIndex: progress.pointIndex, tileMapKey: tileMapKey)
                    status = limitedMap ? .limitedMap : .navigating
                }
                navigationState = Self.state(status)
                sendNavigationUpdate(route: route, progress: progress, location: displayedLocation, status: status)
            }
        } catch is CancellationError {
            return
        } catch {
            navigationState = .failed("NAVIGATION_FAILED")
            errorMessage = "Không thể bắt đầu điều hướng bằng dữ liệu thật."
        }
    }

    private func makeRoute(from location: CLLocation, to destination: GeoPoint, serviceKey: String) async throws -> RoutePlan {
        navigationState = .routing
        return try await routeClient.route(
            origin: location.geoPoint,
            destination: destination,
            serviceKey: serviceKey,
            headingDegrees: location.course >= 0 ? Int(location.course.rounded()) : nil
        )
    }

    private func publish(route: RoutePlan, progressIndex: Int, tileMapKey: String) async throws -> Bool {
        navigationState = .transferring
        let output = try await assetFactory.make(
            input: RouteCardRenderInput(route: route, progressIndex: progressIndex),
            tileMapKey: tileMapKey
        )
        routePreviewPNG = output.asset.data
        await renderCoordinator.start(asset: output.asset)
        guard case .displayed = renderCoordinator.state,
              let sceneID = renderCoordinator.lastDisplayedSceneID else { throw RouteCardAssetFactory.Error.payloadTooLarge }
        activeSceneID = sceneID
        activeAnchorIndex = progressIndex
        navigationManeuver = output.scene.maneuver
        navigationDistanceMeters = output.scene.distanceMeters
        navigationStreet = output.scene.streetName
        navigationState = output.limitedMap ? .limitedMap : .navigating
        return output.limitedMap
    }

    private func sendNavigationUpdate(route: RoutePlan, progress: RouteProgress, location: GeoPoint, status: NavigationStatus) {
        guard let scene = activeSceneID else { return }
        let instruction = route.instructions.first { $0.interval.upperBound >= progress.pointIndex }
        let markerLocation = progress.matchedLocation ?? location
        let marker = RouteCardBuilder.marker(route: route, anchorProgressIndex: activeAnchorIndex, location: markerLocation)
            ?? ScreenPoint(x: 106, y: 320)
        updateSequence += 1
        guard let update = try? NavigationUpdate(
            scene: scene,
            seq: updateSequence,
            x: marker.x,
            y: marker.y,
            maneuver: status == .arrived ? .arrive : (instruction?.maneuver ?? .straight),
            distanceMeters: Self.remainingDistance(route: route, location: location, progressIndex: progress.pointIndex, instruction: instruction),
            street: instruction?.streetName ?? "",
            status: status
        ) else { return }
        navigationManeuver = update.maneuver
        navigationDistanceMeters = update.distanceMeters
        navigationStreet = update.street
        guard let first = updateCoalescer.enqueue(update), updateTask == nil else { return }
        updateTask = Task { @MainActor [weak self] in await self?.drainUpdates(first) }
    }

    private func drainUpdates(_ first: NavigationUpdate) async {
        var next: NavigationUpdate? = first
        while let update = next, !Task.isCancelled {
            do {
                _ = try await session.sendAwaitingAcknowledgement(topic: NavigationUpdate.topic, body: update.jsonBody())
                try await updateClock.sleep(for: .seconds(1))
            } catch {
                updateCoalescer.reset()
                break
            }
            next = updateCoalescer.completed()
        }
        updateTask = nil
    }

    func sendEcho() async {
        guard rpkState == .ready else { return }
        do { _ = try await session.send(topic: "system.echo", body: ["text": .string(echoInput)]) }
        catch { errorMessage = "Không gửi được echo tới band." }
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

    private func consume(_ event: InterconnectEvent) {
        switch event {
        case .connected:
            renderCoordinator.reconnected()
            rpkState = .ready
            sessionState = .applicationReady
        case .disconnected:
            rpkState = .locked
            renderCoordinator.disconnected()
            stopNavigation()
        case let .sent(envelope): append(envelope, delivery: .sent)
        case let .received(envelope):
            renderCoordinator.consume(envelope)
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

    private var destination: GeoPoint? {
        guard let latitude = Double(destinationLatitudeInput), let longitude = Double(destinationLongitudeInput),
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        return GeoPoint(latitude: latitude, longitude: longitude)
    }

    private func loadVietmapKeyHealth() {
        do { hasTileMapKey = try vietmapKeyStore.load(.tileMap) != nil }
        catch { errorMessage = "Không đọc được cấu hình Vietmap trong Keychain." }
        do { hasServiceKey = try vietmapKeyStore.load(.service) != nil }
        catch { errorMessage = "Không đọc được cấu hình Vietmap trong Keychain." }
    }

    private func loadVietmapKey(_ kind: VietmapKeyKind) -> String? { try? vietmapKeyStore.load(kind) }

    private func append(_ envelope: ApplicationEnvelope, delivery: EchoDelivery) {
        guard envelope.topic == "system.echo", case let .string(text)? = envelope.body?["text"] else { return }
        events.append(EchoEntry(id: envelope.id, source: envelope.src, text: text, delivery: delivery))
        if events.count > 40 { events.removeFirst(events.count - 40) }
    }

    private func safeMessage(for error: Swift.Error) -> String {
        switch error {
        case BandAuthenticationError.hmacMismatch: "Xác thực thất bại. Hãy kiểm tra AuthKey."
        case BandAuthenticationError.timeout, BandSessionError.timeout: "Band không phản hồi trong thời gian chờ."
        case BandBLEError.bluetoothUnavailable: "Bluetooth chưa sẵn sàng hoặc chưa được cấp quyền."
        case BandBLEError.serviceMissing, BandBLEError.characteristicMissing: "Thiết bị không có Xiaomi BLE V2 FE95/5E/5F."
        case InterconnectSession.Error.fingerprintMismatch: "Fingerprint RPK đã thay đổi."
        default: "Kết nối thất bại. Hãy đóng Mi Fitness và thử lại."
        }
    }

    private static func state(_ status: NavigationStatus) -> LiveNavigationState {
        switch status {
        case .navigating: .navigating
        case .gpsLow: .gpsLow
        case .limitedMap: .limitedMap
        case .rerouting: .rerouting
        case .arrived: .arrived
        }
    }

    private static func meters(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let latitude = (a.latitude + b.latitude) / 2 * .pi / 180
        return hypot((b.longitude - a.longitude) * 111_320 * cos(latitude), (b.latitude - a.latitude) * 111_132)
    }

    private static func remainingDistance(
        route: RoutePlan,
        location: GeoPoint,
        progressIndex: Int,
        instruction: RouteInstruction?
    ) -> Int {
        guard let instruction else { return 0 }
        let end = min(instruction.interval.upperBound, route.points.count - 1)
        let start = min(progressIndex, end)
        var distance = meters(location, route.points[start])
        if start < end {
            for index in start..<end { distance += meters(route.points[index], route.points[index + 1]) }
        }
        return max(0, Int(distance.rounded()))
    }
}

private extension CLLocation {
    var geoPoint: GeoPoint { GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude) }
}
