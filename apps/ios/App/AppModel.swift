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
enum NavigationRuntimeError: Swift.Error { case bandDisplayFailed(String) }

struct EchoEntry: Identifiable, Equatable, Sendable {
    let id: String
    let source: ApplicationEnvelope.Source
    let text: String
    var delivery: EchoDelivery
}

@MainActor
final class AppModel: ObservableObject {
    static let fixedNavigationMarker = ScreenPoint(x: 106, y: 374)
    private struct SnapshotRefreshRequest {
        let route: RoutePlan
        let progress: RouteProgress
        let location: CLLocation
        let tileMapKey: String
        let bearingDegrees: Double
    }
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
    @Published private(set) var navigationStart: GeoPoint?
    @Published private(set) var navigationDestination: GeoPoint?
    @Published private(set) var navigationRouteDistanceMeters: Int?
    @Published private(set) var navigationAlternativePathCount: Int?
    @Published private(set) var navigationInstructions: [RouteInstruction] = []
    @Published private(set) var navigationDebugEntries: [NavigationDebugEntry] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var locationHealth = "Chưa bắt đầu định vị"
    @Published private(set) var locationNeedsSettings = false
    @Published private(set) var lastMapFixAgeMilliseconds: Int?
    @Published private(set) var latencyViolations = 0

    private let keyStore: any AuthKeyStoreProtocol
    private let vietmapKeyStore: any VietmapKeyStoreProtocol
    private let bandStore: any RememberedBandStoreProtocol
    private let trustedRPKStore: any TrustedRPKStore
    private let central: any BandCentralProtocol
    private let session: BandSession
    private let routeClient: VietmapRouteClient
    private let snapshotRenderer: VietmapSnapshotRenderer
    private let snapshotRender: @MainActor (VietmapSnapshotRequest) async throws -> VietmapSnapshotOutput
    private let locationClient: ForegroundLocationClient
    private let renderCoordinator: RouteCardRenderCoordinator
    private let updateClock: any BlueBandClock
    private let defaults: UserDefaults
    private let scanDuration: Duration
    private var scanGeneration = 0
    private var eventTask: Task<Void, Never>?
    private var navigationTask: Task<Void, Never>?
    private var navigationGeneration = 0
    private var rerouteTask: Task<Void, Never>?
    private var pendingReroute: RoutePlan?
    private var applicationState = "active"
    private var displayedFixTimestamp: Date?
    private var updateTask: Task<Void, Never>?
    private var updateCoalescer = NavigationUpdateCoalescer()
    private var updateSequence = 0
    private var activeSceneID: String?
    private var activeSnapshotConfiguration: VietmapSnapshotConfiguration?
    private var activeSnapshotAnchor: GeoPoint?
    private var lastSnapshotRefreshStartedAt: Date?
    private var snapshotRetryAfter = Date.distantPast
    private var navigationStartedMilliseconds = 0
    private var navigationDebugSequence = 0
    private var navigationScreenIsActive = false
    private var gpsWaitMilliseconds = 0
    private var routeRequestMilliseconds = 0
    private var pendingSnapshotRefresh: SnapshotRefreshRequest?
    private var snapshotRefreshTask: Task<Void, Never>?
    private var guidanceBearingPolicy = GuidanceBearingPolicy()

    init(
        keyStore: any AuthKeyStoreProtocol,
        vietmapKeyStore: any VietmapKeyStoreProtocol,
        bandStore: any RememberedBandStoreProtocol,
        trustedRPKStore: any TrustedRPKStore,
        central: any BandCentralProtocol,
        session: BandSession,
        routeClient: VietmapRouteClient,
        snapshotRenderer: VietmapSnapshotRenderer,
        locationClient: ForegroundLocationClient,
        routeCardSession: (any RouteCardSessionSending)? = nil,
        snapshotRender: (@MainActor (VietmapSnapshotRequest) async throws -> VietmapSnapshotOutput)? = nil,
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
        self.snapshotRenderer = snapshotRenderer
        self.snapshotRender = snapshotRender ?? { try await snapshotRenderer.render($0) }
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
        locationClient.onHealthChange = { [weak self] in
            guard let self else { return }
            locationHealth = locationClient.healthText
            locationNeedsSettings = locationClient.needsSettings
            logNavigation("gps.health", locationClient.diagnostic)
        }
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
            if kind == .tileMap { updateNavigationPrewarming() }
        } catch { errorMessage = "Không lưu được cấu hình Vietmap vào Keychain." }
    }

    func deleteVietmapKey(_ kind: VietmapKeyKind) {
        do {
            try vietmapKeyStore.delete(kind)
            if kind == .tileMap { tileMapKeyInput = ""; hasTileMapKey = false }
            else { serviceKeyInput = ""; hasServiceKey = false }
            if kind == .tileMap { updateNavigationPrewarming() }
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
            } catch {
                if !Task.isCancelled { errorMessage = safeMessage(for: error) }
            }
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
        guard navigationTask == nil else { return }
        guard rpkState == .ready else {
            resetNavigationDebug()
            navigationState = .failed("RPK_NOT_READY")
            errorMessage = "Navigation Failed (RPK_NOT_READY). Hãy kết nối và chờ xác thực band."
            logNavigation("navigation.rejected", "reason=RPK_NOT_READY")
            return
        }
        guard let destination, let serviceKey = loadVietmapKey(.service) else {
            resetNavigationDebug()
            navigationState = .failed("CONFIG_MISSING")
            errorMessage = "Navigation Failed (CONFIG_MISSING). Hãy lưu tọa độ đích và Service/API key."
            logNavigation("navigation.rejected", "reason=CONFIG_MISSING")
            return
        }
        saveDestination()
        resetNavigationDebug()
        navigationDestination = destination
        let tileMapAvailability = loadVietmapKey(.tileMap)?.isEmpty == false ? "present" : "absent"
        logNavigation(
            "navigation.start",
            "destination=\(NavigationDebugFormatter.coordinateSummary(destination)) " +
            "serviceKey=present tileMapKey=\(tileMapAvailability)"
        )
        navigationGeneration += 1
        snapshotRetryAfter = .distantPast
        let generation = navigationGeneration
        navigationTask = Task { @MainActor [weak self] in
            await self?.runNavigation(
                destination: destination,
                serviceKey: serviceKey,
                tileMapKey: self?.loadVietmapKey(.tileMap) ?? "",
                generation: generation
            )
        }
    }

    func stopNavigation() {
        navigationGeneration += 1
        rerouteTask?.cancel()
        rerouteTask = nil
        pendingReroute = nil
        renderCoordinator.cancel()
        snapshotRefreshTask?.cancel()
        snapshotRefreshTask = nil
        pendingSnapshotRefresh = nil
        navigationTask?.cancel()
        navigationTask = nil
        updateTask?.cancel()
        updateTask = nil
        updateCoalescer.reset()
        locationClient.stop()
        activeSceneID = nil
        activeSnapshotConfiguration = nil
        activeSnapshotAnchor = nil
        lastSnapshotRefreshStartedAt = nil
        snapshotRetryAfter = .distantPast
        guidanceBearingPolicy = GuidanceBearingPolicy()
        routePreviewPNG = nil
        navigationState = .idle
    }

    func navigationScreenActive(_ active: Bool) {
        navigationScreenIsActive = active
        updateNavigationPrewarming()
    }

    func applicationStateChanged(_ state: String) {
        applicationState = state
        locationClient.applicationActive(state == "active")
        snapshotRenderer.setApplicationActive(state == "active")
        updateNavigationPrewarming()
        logNavigation("app.state", state)
    }

    private func updateNavigationPrewarming() {
        if navigationScreenIsActive, rpkState == .ready, applicationState == "active" {
            locationClient.startPrewarming()
            if let key = loadVietmapKey(.tileMap) { snapshotRenderer.prewarm(tileMapKey: key) }
            else { snapshotRenderer.stopPrewarming() }
        } else {
            locationClient.stopPrewarming()
            snapshotRenderer.stopPrewarming()
        }
    }

    private func runNavigation(destination: GeoPoint, serviceKey: String, tileMapKey: String, generation: Int) async {
        defer {
            if generation == navigationGeneration {
                locationClient.stop()
                rerouteTask?.cancel()
                rerouteTask = nil
                pendingReroute = nil
                snapshotRefreshTask?.cancel()
                snapshotRefreshTask = nil
                pendingSnapshotRefresh = nil
                navigationTask = nil
            }
        }
        let gpsStarted = Self.nowMilliseconds()
        navigationState = .waitingForGPS
        sendStartupStatus("locating")
        logNavigation("gps.wait", "requiredAccuracyM=25")
        do {
            var iterator = locationClient.locations().makeAsyncIterator()
            var first = locationClient.recentLocation()
            if first == nil {
                while let location = try await iterator.next() {
                    guard !Task.isCancelled else { return }
                    if location.horizontalAccuracy <= 25 { first = location; break }
                    navigationState = .gpsLow
                    sendStartupStatus("gpsLow")
                    logNavigation("gps.low", "accuracyM=\(Int(location.horizontalAccuracy.rounded()))")
                }
            }
            guard !Task.isCancelled else { return }
            guard var first else { throw ForegroundLocationClient.Error.unavailable }
            gpsWaitMilliseconds = max(0, Self.nowMilliseconds() - gpsStarted)
            navigationStart = first.geoPoint
            logNavigation(
                "gps.fix",
                "start=\(NavigationDebugFormatter.coordinateSummary(first.geoPoint)) " +
                "accuracyM=\(Int(first.horizontalAccuracy.rounded()))"
            )
            var route = try await makeRoute(
                from: first,
                to: destination,
                serviceKey: serviceKey,
                heading: Self.initialRouteHeading(
                    courseDegrees: first.course,
                    speedMetersPerSecond: first.speed
                ),
                generation: generation
            )
            try checkNavigationOwner(generation)
            first = locationClient.recentLocation() ?? first
            var tracker = RouteProgressTracker()
            var progress = tracker.update(route: route, location: first.geoPoint, horizontalAccuracyMeters: first.horizontalAccuracy)
            var selection = GuidancePresentationPolicy.select(
                route: route,
                progress: progress,
                horizontalAccuracyMeters: first.horizontalAccuracy
            )
            let initialRouteBearing = GuidancePresentationPolicy.stationaryBearing(
                route: route,
                progress: progress,
                selection: selection
            )
            var bearing = guidanceBearingPolicy.update(
                horizontalAccuracyMeters: first.horizontalAccuracy,
                speedMetersPerSecond: first.speed,
                courseDegrees: first.course,
                routeBearingDegrees: initialRouteBearing,
                confirmedBearingDegrees: initialRouteBearing,
                secondsSinceRefresh: .infinity
            )
            scheduleRefresh(
                route: route, progress: progress, location: first,
                tileMapKey: tileMapKey, bearingDegrees: bearing.bearingDegrees, reason: "initial"
            )
            var lastReroute = Date.distantPast
            var lastGoodLocation = first.geoPoint
            sendNavigationUpdate(
                route: route,
                progress: progress,
                location: first.geoPoint,
                headingDegrees: first.course,
                horizontalAccuracyMeters: first.horizontalAccuracy,
                status: .navigating
            )

            while let location = try await iterator.next() {
                try checkNavigationOwner(generation)
                if let replacement = pendingReroute {
                    pendingReroute = nil
                    route = replacement
                    tracker = RouteProgressTracker()
                    activeSnapshotAnchor = nil
                }
                progress = tracker.update(route: route, location: location.geoPoint, horizontalAccuracyMeters: location.horizontalAccuracy)
                let goodFix = location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 25
                if goodFix { lastGoodLocation = location.geoPoint }
                let displayedLocation = goodFix ? location.geoPoint : lastGoodLocation
                selection = GuidancePresentationPolicy.select(
                    route: route,
                    progress: progress,
                    horizontalAccuracyMeters: location.horizontalAccuracy
                )
                let routeBearing = GuidancePresentationPolicy.stationaryBearing(
                    route: route,
                    progress: progress,
                    selection: selection
                )
                bearing = guidanceBearingPolicy.update(
                    horizontalAccuracyMeters: location.horizontalAccuracy,
                    speedMetersPerSecond: location.speed,
                    courseDegrees: location.course,
                    routeBearingDegrees: routeBearing,
                    confirmedBearingDegrees: activeSnapshotConfiguration?.heading ?? routeBearing,
                    secondsSinceRefresh: lastSnapshotRefreshStartedAt.map { Date().timeIntervalSince($0) } ?? .infinity
                )
                if goodFix && Self.meters(location.geoPoint, destination) <= 25 {
                    navigationState = .arrived
                    sendNavigationUpdate(route: route, progress: progress, location: displayedLocation, headingDegrees: location.course, horizontalAccuracyMeters: location.horizontalAccuracy, status: .arrived)
                    return
                }
                if progress.shouldReroute, rerouteTask == nil, Date().timeIntervalSince(lastReroute) >= 15 {
                    navigationState = .rerouting
                    sendNavigationUpdate(route: route, progress: progress, location: displayedLocation, headingDegrees: location.course, horizontalAccuracyMeters: location.horizontalAccuracy, status: .rerouting)
                    lastReroute = Date()
                    rerouteTask = Task { @MainActor [weak self] in
                        guard let self else { return }
                        defer { if generation == navigationGeneration { rerouteTask = nil } }
                        do {
                            let replacement = try await makeRoute(
                                from: location, to: destination, serviceKey: serviceKey,
                                heading: Self.routeHeading(courseDegrees: location.course), generation: generation
                            )
                            try checkNavigationOwner(generation)
                            pendingReroute = replacement
                        } catch is CancellationError {
                        } catch {
                            guard generation == navigationGeneration else { return }
                            logNavigation("route.reroute.failed", "code=\(Self.navigationErrorCode(for: error))")
                        }
                    }
                }
                let status: NavigationStatus = progress.status == .gpsLow ? .gpsLow : .navigating
                let instruction = selection?.instruction
                let markerPoint = activeSnapshotConfiguration?.point(for: displayedLocation)
                let nextManeuverVisible = instruction.flatMap {
                    route.points.indices.contains($0.interval.upperBound)
                        ? activeSnapshotConfiguration?.point(for: route.points[$0.interval.upperBound]) : nil
                }.map { (0..<212).contains(Int($0.x)) && (0..<520).contains(Int($0.y)) } ?? false
                let refreshContext = SnapshotRefreshContext(
                    marker: markerPoint.map { ScreenPoint(x: Int($0.x.rounded()), y: Int($0.y.rounded())) },
                    safeViewport: SnapshotRefreshPolicy.defaultSafeViewport,
                    distanceFromAnchorMeters: activeSnapshotAnchor.map { Self.meters($0, displayedLocation) } ?? .infinity,
                    secondsSinceLastRefresh: lastSnapshotRefreshStartedAt.map { Date().timeIntervalSince($0) } ?? .infinity,
                    nextManeuverVisible: nextManeuverVisible
                )
                let viewportShouldRefresh = SnapshotRefreshPolicy.shouldRefresh(refreshContext)
                let refreshReason = status == .gpsLow ? "gpsLow" :
                    bearing.shouldRefresh ? "bearing" : viewportShouldRefresh ? "viewport" : "none"
                // Keep the newest fix even inside the cooldown. The drain waits until due,
                // so the final fix is not lost if the user stops before another callback.
                if status != .gpsLow && (bearing.shouldRefresh || viewportShouldRefresh ||
                    refreshContext.distanceFromAnchorMeters >= 1 || snapshotRefreshTask != nil) {
                    scheduleRefresh(
                        route: route, progress: progress, location: location,
                        tileMapKey: tileMapKey, bearingDegrees: bearing.bearingDegrees, reason: refreshReason
                    )
                }
                navigationState = Self.state(status)
                sendNavigationUpdate(route: route, progress: progress, location: displayedLocation, headingDegrees: location.course, horizontalAccuracyMeters: location.horizontalAccuracy, status: status)
                let routeDistance = progress.distanceFromRouteMeters.isFinite
                    ? String(Int(progress.distanceFromRouteMeters.rounded())) : "unknown"
                logNavigation(
                    "guidance.fix",
                    "ageMs=\(Int(max(0, Date().timeIntervalSince(location.timestamp) * 1_000).rounded())) accuracyM=\(Int(max(0, location.horizontalAccuracy).rounded())) " +
                    "speedMps=\(String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), location.speed)) course=\(Int(location.course.rounded())) " +
                    "routeDistanceM=\(routeDistance) segment=\(progress.matchedSegmentIndex) fraction=\(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), progress.matchedFraction)) " +
                    "instruction=\(selection?.instructionIndex ?? -1) remainingM=\(Int((selection?.distanceMeters ?? 0).rounded())) " +
                    "bearing=\(Int(bearing.bearingDegrees.rounded())) source=\(bearing.source.rawValue) delta=\(Int(bearing.deltaDegrees.rounded())) refresh=\(refreshReason)"
                )
            }
        } catch is CancellationError {
            return
        } catch {
            guard generation == navigationGeneration else { return }
            let code = Self.navigationErrorCode(for: error)
            navigationState = .failed(code)
            errorMessage = "Navigation Failed (\(code)). Mở Debug log để xem từng bước."
            logNavigation("navigation.failed", "code=\(code) \(Self.navigationErrorDetail(for: error))")
        }
    }

    private func sendStartupStatus(_ status: String) {
        let session = session
        Task {
            _ = try? await session.sendAwaitingAcknowledgement(
                topic: "nav.status",
                body: ["status": .string(status)]
            )
        }
    }

    private func makeRoute(
        from location: CLLocation,
        to destination: GeoPoint,
        serviceKey: String,
        heading: Int?,
        generation: Int
    ) async throws -> RoutePlan {
        navigationState = .routing
        let started = Self.nowMilliseconds()
        logNavigation(
            "route.request",
            "origin=\(NavigationDebugFormatter.coordinateSummary(location.geoPoint)) " +
            "destination=\(NavigationDebugFormatter.coordinateSummary(destination)) " +
            "heading=\(heading.map(String.init) ?? "unknown") " +
            "speedMps=\(location.speed.isFinite ? String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), location.speed) : "unknown")"
        )
        let route = try await routeClient.route(
            origin: location.geoPoint,
            destination: destination,
            serviceKey: serviceKey,
            headingDegrees: heading
        )
        try checkNavigationOwner(generation)
        routeRequestMilliseconds += max(0, Self.nowMilliseconds() - started)
        navigationRouteDistanceMeters = Int(route.distanceMeters.rounded())
        navigationAlternativePathCount = route.alternativePathCount
        navigationInstructions = route.instructions
        logNavigation(
            "route.response",
            "distanceM=\(navigationRouteDistanceMeters ?? 0) points=\(route.points.count) " +
            "instructions=\(route.instructions.count) paths=\(route.alternativePathCount)"
        )
        return route
    }

    private func publish(
        route: RoutePlan,
        progress: RouteProgress,
        location: CLLocation,
        tileMapKey: String,
        bearingDegrees: Double,
        generation: Int
    ) async throws -> Bool {
        try checkNavigationOwner(generation)
        navigationState = .transferring
        let snapshotStartedAt = Date()
        lastSnapshotRefreshStartedAt = snapshotStartedAt
        logNavigation("map.render.start", "session=\(generation) fixAgeMs=\(Int(max(0, Date().timeIntervalSince(location.timestamp) * 1000))) app=\(applicationState)")
        let selection = GuidancePresentationPolicy.select(
            route: route,
            progress: progress,
            horizontalAccuracyMeters: location.horizontalAccuracy
        )
        let instruction = selection?.instruction ?? route.instructions.first { $0.interval.upperBound >= progress.pointIndex }
        let maneuverIndex = min(instruction?.interval.upperBound ?? route.points.count - 1, route.points.count - 1)
        let forwardPoint = GuidancePresentationPolicy.forwardPoint(
            route: route,
            progress: progress,
            selection: selection
        ) ?? route.points[maneuverIndex]
        let snapshot = try await snapshotRender(VietmapSnapshotRequest(
            route: route,
            matchedPosition: progress.matchedLocation ?? location.geoPoint,
            overlayGeometry: selection.map {
                RouteOverlayGeometry.make(route: route, progress: progress, selection: $0)
            } ?? RouteOverlayGeometry(
                subdued: route.points,
                traveled: Array(route.points.prefix(progress.pointIndex + 1)),
                active: Array(route.points.dropFirst(progress.pointIndex)),
                context: []
            ),
            headingDegrees: bearingDegrees,
            nextManeuver: forwardPoint,
            tileMapKey: tileMapKey,
            profile: .colors16Labels
        ))
        try checkNavigationOwner(generation)
        let encoded = try SnapshotImageEncoder.encode(snapshot.image)
        let asset = try RenderAsset(
            kind: .raster,
            format: encoded.format,
            formatVersion: RenderProtocol.formatVersion,
            width: RenderProtocol.viewportWidth,
            height: RenderProtocol.viewportHeight,
            data: encoded.data,
            primitives: 0
        )
        logNavigation(
            "map.rendered",
            "cache=\(snapshot.cacheState) bytes=\(asset.byteCount) format=\(encoded.format.rawValue) jpegQuality=\(encoded.jpegQuality ?? 0) " +
            "palette=\(encoded.colorCount) pixelBlock=\(encoded.pixelBlockSize) zoom=\(Int(snapshot.zoom)) " +
            "layers=\(snapshot.retainedFillLayers)/\(snapshot.retainedLineLayers)/\(snapshot.retainedSymbolLayers) " +
            "styleMs=\(snapshot.styleLoadMilliseconds) snapshotMs=\(snapshot.snapshotMilliseconds) encodeMs=\(encoded.durationMilliseconds)"
        )
        let safeMask = BandDisplaySafeMask.smartBand10PhotoEstimate
        let marker = Self.fixedNavigationMarker
        let destination = destinationPresentation(
            status: .navigating,
            marker: marker,
            mask: safeMask,
            configuration: snapshot.configuration
        )
        let preview = try RenderNavigationPreview(
            maneuver: instruction?.maneuver ?? .straight,
            distanceMeters: max(0, Int((selection?.distanceMeters ?? 0).rounded())),
            street: instruction?.streetName ?? "",
            x: marker.x,
            y: marker.y,
            headingBucket: 0,
            destinationMode: destination.mode,
            destinationX: destination.point.x,
            destinationY: destination.point.y
        )
        logNavigation("map.transfer.start", "session=\(generation) bytes=\(asset.byteCount)")
        await renderCoordinator.start(asset: asset, diagnostics: RouteCardRenderDiagnostics(
            gpsWaitMilliseconds: gpsWaitMilliseconds,
            routeRequestMilliseconds: routeRequestMilliseconds,
            styleLoadMilliseconds: snapshot.styleLoadMilliseconds,
            snapshotMilliseconds: snapshot.snapshotMilliseconds,
            paletteReductionMilliseconds: encoded.durationMilliseconds,
            paletteSize: encoded.colorCount,
            retainedFillLayers: snapshot.retainedFillLayers,
            retainedLineLayers: snapshot.retainedLineLayers,
            retainedSymbolLayers: snapshot.retainedSymbolLayers,
            cacheState: snapshot.cacheState
        ), preview: preview)
        try checkNavigationOwner(generation)
        guard case .displayed = renderCoordinator.state,
              let sceneID = renderCoordinator.lastDisplayedSceneID else {
            throw NavigationRuntimeError.bandDisplayFailed(renderCoordinator.failureCode ?? "BAND_RESULT_MISSING")
        }
        activeSceneID = sceneID
        routePreviewPNG = asset.data
        lastMapFixAgeMilliseconds = Int(max(0, Date().timeIntervalSince(location.timestamp) * 1000))
        displayedFixTimestamp = location.timestamp
        if lastMapFixAgeMilliseconds! >= 5_000 { latencyViolations += 1 }
        activeSnapshotConfiguration = snapshot.configuration
        activeSnapshotAnchor = progress.matchedLocation ?? location.geoPoint
        navigationManeuver = instruction?.maneuver ?? .straight
        navigationDistanceMeters = max(0, Int((selection?.distanceMeters ?? 0).rounded()))
        navigationStreet = instruction?.streetName ?? ""
        navigationState = .navigating
        logNavigation(
            "band.displayed",
            "scene=\(sceneID) status=\(navigationStateCode) bearing=\(Int(bearingDegrees.rounded())) " +
            "fixAgeMs=\(Int(max(0, Date().timeIntervalSince(location.timestamp) * 1_000).rounded())) " +
            "publishMs=\(Int(max(0, Date().timeIntervalSince(snapshotStartedAt) * 1_000).rounded()))"
        )
        return false
    }

    private func scheduleRefresh(
        route: RoutePlan,
        progress: RouteProgress,
        location: CLLocation,
        tileMapKey: String,
        bearingDegrees: Double,
        reason: String
    ) {
        let queued = snapshotRefreshTask != nil
        pendingSnapshotRefresh = SnapshotRefreshRequest(
            route: route,
            progress: progress,
            location: location,
            tileMapKey: tileMapKey,
            bearingDegrees: bearingDegrees
        )
        logNavigation(
            "map.refresh.scheduled",
            "reason=\(reason) bearing=\(Int(bearingDegrees.rounded())) " +
            "fixAgeMs=\(Int(max(0, Date().timeIntervalSince(location.timestamp) * 1_000).rounded())) queued=\(queued)"
        )
        guard snapshotRefreshTask == nil else { return }
        let generation = navigationGeneration
        snapshotRefreshTask = Task { @MainActor [weak self] in
            await self?.drainSnapshotRefreshes(generation: generation)
        }
    }

    private func drainSnapshotRefreshes(generation: Int) async {
        defer { if generation == navigationGeneration { snapshotRefreshTask = nil } }
        while !Task.isCancelled, generation == navigationGeneration, pendingSnapshotRefresh != nil {
            let delay = max(0, snapshotRetryAfter.timeIntervalSinceNow,
                            1 - (lastSnapshotRefreshStartedAt.map { Date().timeIntervalSince($0) } ?? 1))
            do { if delay > 0 { try await Task.sleep(for: .seconds(delay)) } } catch { return }
            guard generation == navigationGeneration, !Task.isCancelled,
                  let request = pendingSnapshotRefresh else { return }
            pendingSnapshotRefresh = nil
            do {
                _ = try await publish(
                    route: request.route,
                    progress: request.progress,
                    location: request.location,
                    tileMapKey: request.tileMapKey,
                    bearingDegrees: request.bearingDegrees,
                    generation: generation
                )
                sendNavigationUpdate(
                    route: request.route,
                    progress: request.progress,
                    location: request.location.geoPoint,
                    headingDegrees: request.location.course,
                    horizontalAccuracyMeters: request.location.horizontalAccuracy,
                    status: .navigating
                )
            } catch is CancellationError {
                if Task.isCancelled { break }
                // The SDK is cancelled when iOS becomes inactive. Keep the final fix
                // for the CPU path even if movement stops before another GPS callback.
                if pendingSnapshotRefresh == nil { pendingSnapshotRefresh = request }
            } catch {
                guard generation == navigationGeneration else { return }
                snapshotRetryAfter = Date().addingTimeInterval(5)
                navigationState = .limitedMap
                sendNavigationUpdate(
                    route: request.route,
                    progress: request.progress,
                    location: request.location.geoPoint,
                    headingDegrees: request.location.course,
                    horizontalAccuracyMeters: request.location.horizontalAccuracy,
                    status: .limitedMap
                )
                logNavigation("map.refresh.failed", "code=\(Self.navigationErrorCode(for: error)) \(Self.navigationErrorDetail(for: error))")
            }
        }
    }

    private func checkNavigationOwner(_ generation: Int) throws {
        guard generation == navigationGeneration, !Task.isCancelled else { throw CancellationError() }
    }

    private func sendNavigationUpdate(
        route: RoutePlan,
        progress: RouteProgress,
        location _: GeoPoint,
        headingDegrees _: Double,
        horizontalAccuracyMeters: Double,
        status: NavigationStatus
    ) {
        guard let scene = activeSceneID else { return }
        let selection = GuidancePresentationPolicy.select(
            route: route,
            progress: progress,
            horizontalAccuracyMeters: horizontalAccuracyMeters
        )
        let instruction = selection?.instruction ?? route.instructions.first { $0.interval.upperBound >= progress.pointIndex }
        let safeMask = BandDisplaySafeMask.smartBand10PhotoEstimate
        let marker = Self.fixedNavigationMarker
        let destination = destinationPresentation(status: status, marker: marker, mask: safeMask)
        updateSequence += 1
        guard let update = try? NavigationUpdate(
            scene: scene,
            seq: updateSequence,
            x: marker.x,
            y: marker.y,
            maneuver: status == .arrived ? .arrive : (instruction?.maneuver ?? .straight),
            headingBucket: 0,
            distanceMeters: max(0, Int((selection?.distanceMeters ?? 0).rounded())),
            street: instruction?.streetName ?? "",
            status: status,
            destinationMode: destination.mode,
            destinationX: destination.point.x,
            destinationY: destination.point.y
        ) else { return }
        navigationManeuver = update.maneuver
        navigationDistanceMeters = update.distanceMeters
        navigationStreet = update.street
        logNavigation(
            "nav.update",
            "maneuver=\(update.maneuver.rawValue) distanceM=\(update.distanceMeters) " +
            "status=\(update.status.rawValue) marker=\(update.x),\(update.y) " +
            "destination=\(update.destinationMode.rawValue),\(update.destinationX),\(update.destinationY)"
        )
        guard let first = updateCoalescer.enqueue(update), updateTask == nil else { return }
        let generation = navigationGeneration
        updateTask = Task { @MainActor [weak self] in await self?.drainUpdates(first, generation: generation) }
    }

    static func headingBucket(_ degrees: Double) -> Int {
        let normalized = degrees.truncatingRemainder(dividingBy: 360)
        let positive = normalized < 0 ? normalized + 360 : normalized
        return Int((positive + 22.5) / 45) % 8
    }

    private func destinationPresentation(
        status: NavigationStatus,
        marker: ScreenPoint,
        mask: BandDisplaySafeMask,
        configuration suppliedConfiguration: VietmapSnapshotConfiguration? = nil
    ) -> (mode: DestinationPresentationMode, point: ScreenPoint) {
        guard status != .arrived,
              let destination = navigationDestination,
              let configuration = suppliedConfiguration ?? activeSnapshotConfiguration else {
            return (.hidden, ScreenPoint(x: 0, y: 0))
        }
        let projected = configuration.point(for: destination)
        guard projected.x.isFinite, projected.y.isFinite else { return (.hidden, ScreenPoint(x: 0, y: 0)) }
        let target = ScreenPoint(
            x: Int(max(-100_000, min(100_000, projected.x)).rounded()),
            y: Int(max(-100_000, min(100_000, projected.y)).rounded())
        )
        if mask.contains(center: target, resourceWidth: 28, resourceHeight: 34) { return (.visible, target) }
        return (.edge, mask.destinationEdge.destinationEdgePoint(from: marker, toward: target))
    }

    static func initialRouteHeading(courseDegrees: Double, speedMetersPerSecond: Double) -> Int? {
        guard speedMetersPerSecond.isFinite, speedMetersPerSecond >= 1 else { return nil }
        return routeHeading(courseDegrees: courseDegrees)
    }

    static func routeHeading(courseDegrees: Double) -> Int? {
        guard courseDegrees.isFinite, (0...360).contains(courseDegrees) else { return nil }
        return Int(courseDegrees.rounded())
    }

    var navigationStartText: String { Self.fullCoordinate(navigationStart) }
    var liveLocationHealth: String { locationClient.healthText }
    var navigationDestinationText: String { Self.fullCoordinate(navigationDestination) }

    var navigationStateCode: String {
        switch navigationState {
        case .idle: "idle"
        case .waitingForGPS: "waitingForGPS"
        case .routing: "routing"
        case .transferring: "transferring"
        case .navigating: "navigating"
        case .gpsLow: "gpsLow"
        case .limitedMap: "limitedMap"
        case .rerouting: "rerouting"
        case .arrived: "arrived"
        case let .failed(code): "failed:\(code)"
        }
    }

    var navigationDebugExport: String {
        NavigationDebugFormatter.export(
            state: navigationStateCode,
            start: navigationStart,
            destination: navigationDestination,
            routeDistanceMeters: navigationRouteDistanceMeters.map(Double.init),
            alternativePathCount: navigationAlternativePathCount,
            instructions: navigationInstructions,
            entries: navigationDebugEntries,
            build: "\(BlueBandProduct.version) (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"))",
            runtime: [
                "app": applicationState,
                "location": locationClient.diagnostic,
                "locationHealth": locationClient.healthText,
                "mapLatency": "fixToDisplayMs=\(lastMapFixAgeMilliseconds.map(String.init) ?? "none") violations=\(latencyViolations)",
                "mapFreshness": "displayedFixAgeMs=\(displayedFixTimestamp.map { Int(max(0, Date().timeIntervalSince($0) * 1000)) }.map(String.init) ?? "none")"
            ]
        )
    }

    private func resetNavigationDebug() {
        navigationStartedMilliseconds = Self.nowMilliseconds()
        gpsWaitMilliseconds = 0
        routeRequestMilliseconds = 0
        lastMapFixAgeMilliseconds = nil
        displayedFixTimestamp = nil
        latencyViolations = 0
        navigationDebugSequence = 0
        navigationDebugEntries = []
        navigationStart = nil
        navigationDestination = nil
        navigationRouteDistanceMeters = nil
        navigationAlternativePathCount = nil
        navigationInstructions = []
        navigationManeuver = .straight
        navigationDistanceMeters = 0
        navigationStreet = ""
        routePreviewPNG = nil
        errorMessage = nil
    }

    private func logNavigation(_ stage: String, _ detail: String) {
        navigationDebugSequence += 1
        let entry = NavigationDebugEntry(
            sequence: navigationDebugSequence,
            elapsedMilliseconds: max(0, Self.nowMilliseconds() - navigationStartedMilliseconds),
            stage: stage,
            detail: detail
        )
        navigationDebugEntries.append(entry)
        if navigationDebugEntries.count > 120 {
            navigationDebugEntries.removeFirst(navigationDebugEntries.count - 120)
        }
    }

    private func drainUpdates(_ first: NavigationUpdate, generation: Int) async {
        defer { if generation == navigationGeneration { updateTask = nil } }
        var next: NavigationUpdate? = first
        while let update = next, !Task.isCancelled, generation == navigationGeneration {
            do {
                _ = try await session.sendAwaitingAcknowledgement(topic: NavigationUpdate.topic, body: update.jsonBody())
                try await updateClock.sleep(for: .seconds(1))
                try checkNavigationOwner(generation)
            } catch {
                guard generation == navigationGeneration else { return }
                updateCoalescer.reset()
                if !Task.isCancelled { logNavigation("nav.delivery.failed", "scene=\(update.scene)") }
                break
            }
            next = updateCoalescer.completed()
        }
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

    func consume(_ event: InterconnectEvent) {
        switch event {
        case .connected:
            renderCoordinator.reconnected()
            rpkState = .ready
            sessionState = .applicationReady
            updateNavigationPrewarming()
        case .disconnected:
            rpkState = .locked
            renderCoordinator.disconnected()
            stopNavigation()
            updateNavigationPrewarming()
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

    private static func navigationErrorCode(for error: Swift.Error) -> String {
        switch error {
        case VietmapRouteClient.Error.invalidRequest: "ROUTE_INVALID_REQUEST"
        case let VietmapRouteClient.Error.httpStatus(status): "ROUTE_HTTP_\(status)"
        case VietmapRouteClient.Error.wrongContentType: "ROUTE_CONTENT_TYPE"
        case VietmapRouteClient.Error.invalidResponse: "ROUTE_RESPONSE_INVALID"
        case let VietmapRouteClient.Error.provider(code): "ROUTE_PROVIDER_\(safeErrorCode(code))"
        case ForegroundLocationClient.Error.unavailable: "GPS_UNAVAILABLE"
        case ForegroundLocationClient.Error.permissionDenied: "GPS_PERMISSION_DENIED"
        case VietmapSnapshotRenderer.Error.backgroundUnavailable: "MAP_BACKGROUND_UNAVAILABLE"
        case VietmapSnapshotRenderer.Error.timedOut: "MAP_RENDER_TIMEOUT"
        case VietmapSnapshotRenderer.Error.provider: "MAP_PROVIDER_FAILED"
        case VietmapSnapshotRenderer.Error.invalidRequest: "MAP_INVALID_REQUEST"
        case VietmapSnapshotRenderer.Error.styleLoadFailed: "MAP_STYLE_FAILED"
        case let VietmapStyleError.httpStatus(status): "MAP_STYLE_HTTP_\(status)"
        case let RouteCardAssetFactory.Error.tileHTTPStatus(status): "MAP_TILE_HTTP_\(status)"
        case is VietmapStyleError: "MAP_STYLE_INVALID"
        case is MapboxVectorTile.Error: "MAP_TILE_INVALID"
        case VietmapSnapshotRenderer.Error.snapshotFailed, VietmapSnapshotRenderer.Error.imageUnavailable: "MAP_SNAPSHOT_FAILED"
        case SnapshotImageEncoder.Error.payloadTooLarge: "MAP_PAYLOAD_TOO_LARGE"
        case NavigationRuntimeError.bandDisplayFailed: "BAND_DISPLAY_FAILED"
        default: "NAVIGATION_ERROR"
        }
    }

    private static func navigationErrorDetail(for error: Swift.Error) -> String {
        switch error {
        case let SnapshotImageEncoder.Error.payloadTooLarge(bytes):
            "encodedBytes=\(bytes) budgetBytes=\(RenderProtocol.maximumPayloadBytes)"
        case let NavigationRuntimeError.bandDisplayFailed(code):
            "terminal=\(safeErrorCode(code))"
        case let VietmapSnapshotRenderer.Error.provider(stage, domain, code):
            "stage=\(safeErrorCode(stage)) domain=\(safeErrorCode(domain)) code=\(code)"
        default: ""
        }
    }

    private static func safeErrorCode(_ value: String) -> String {
        let allowed = value.uppercased().map { character in
            character.isLetter || character.isNumber || character == "_" || character == "-" ? character : "_"
        }
        return String(allowed.prefix(32))
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

    private static func fullCoordinate(_ point: GeoPoint?) -> String {
        guard let point else { return "—" }
        return String(
            format: "%.6f,%.6f",
            locale: Locale(identifier: "en_US_POSIX"),
            point.latitude,
            point.longitude
        )
    }

    private static func nowMilliseconds() -> Int {
        Int(Date().timeIntervalSince1970 * 1_000)
    }

}

private extension CLLocation {
    var geoPoint: GeoPoint { GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude) }
}
