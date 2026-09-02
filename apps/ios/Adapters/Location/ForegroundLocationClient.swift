import CoreLocation
import Foundation
import BlueBandMapCore

@MainActor
final class ForegroundLocationClient: NSObject, CLLocationManagerDelegate {
    enum Error: Swift.Error { case permissionDenied, unavailable }

    private let manager: CLLocationManager
    private var continuation: AsyncThrowingStream<CLLocation, Swift.Error>.Continuation?
    private var cachedLocation: CLLocation?
    private var prewarming = false
    private var navigationActive = false
    private var backgroundActivitySession: CLBackgroundActivitySession?
    private var generation = 0
    private var applicationActive = true
    private var requestedPrecision = false
    private let makeBackgroundActivity: @MainActor () -> CLBackgroundActivitySession?
    private let servicesEnabled: @Sendable () -> Bool
    private var servicesAvailable: Bool?
    private var servicesCheckTask: Task<Void, Never>?
    private var servicesCheckPending = false
    private(set) var rawFixCount = 0
    private(set) var acceptedFixCount = 0
    private(set) var lastEvent = "idle"
    private var lastError = "none"
    var onHealthChange: (() -> Void)?

    override convenience init() {
        self.init(manager: CLLocationManager())
    }

    init(
        manager: CLLocationManager,
        makeBackgroundActivity: @escaping @MainActor () -> CLBackgroundActivitySession? = { CLBackgroundActivitySession() },
        servicesEnabled: @escaping @Sendable () -> Bool = { CLLocationManager.locationServicesEnabled() }
    ) {
        self.manager = manager
        self.makeBackgroundActivity = makeBackgroundActivity
        self.servicesEnabled = servicesEnabled
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = 1
        manager.pausesLocationUpdatesAutomatically = false
    }

    func locations() -> AsyncThrowingStream<CLLocation, Swift.Error> {
        stop(reason: "replaced")
        generation += 1
        let owner = generation
        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            self.continuation = continuation
            self.navigationActive = true
            self.requestedPrecision = false
            if let recentLocation = self.recentLocation() { continuation.yield(recentLocation) }
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor in
                    guard self?.generation == owner else { return }
                    self?.stop(reason: "consumerEnded")
                }
            }
            refreshServicesAvailability()
            reconcileAuthorization()
        }
    }

    func startPrewarming() {
        prewarming = true
        refreshServicesAvailability()
        reconcileAuthorization()
    }

    func stopPrewarming() {
        prewarming = false
        if continuation == nil { manager.stopUpdatingLocation() }
    }

    func applicationActive(_ active: Bool) {
        applicationActive = active
        if active {
            refreshServicesAvailability()
            reconcileAuthorization()
        }
        onHealthChange?()
    }

    func recentLocation(now: Date = Date()) -> CLLocation? {
        guard servicesAvailable != false,
              manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse,
              manager.accuracyAuthorization == .fullAccuracy,
              let cachedLocation,
              ReusableLocationPolicy.isReusable(
                horizontalAccuracyMeters: cachedLocation.horizontalAccuracy,
                ageSeconds: now.timeIntervalSince(cachedLocation.timestamp)
              ) else { return nil }
        return cachedLocation
    }

    func stop(reason: String = "stopped") {
        generation += 1
        navigationActive = false
        let ended = continuation
        continuation = nil
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        backgroundActivitySession?.invalidate()
        backgroundActivitySession = nil
        if !prewarming { manager.stopUpdatingLocation() }
        ended?.finish()
        record(reason)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshServicesAvailability()
        reconcileAuthorization()
    }

    private func refreshServicesAvailability() {
        servicesCheckPending = true
        servicesAvailable = nil
        guard servicesCheckTask == nil else { return }
        // Core Location's synchronous global query may block. Never run it for each
        // fix or UI tick, and coalesce overlapping lifecycle requests into one probe.
        servicesCheckTask = Task { @MainActor [weak self, servicesEnabled] in
            repeat {
                self?.servicesCheckPending = false
                let available = await Task.detached(priority: .utility) { servicesEnabled() }.value
                guard let self else { return }
                if !servicesCheckPending {
                    servicesAvailable = available
                    reconcileAuthorization()
                }
            } while self?.servicesCheckPending == true
            self?.servicesCheckTask = nil
        }
    }

    private func reconcileAuthorization() {
        guard prewarming || navigationActive else { onHealthChange?(); return }
        guard servicesAvailable != false else { fail(Error.unavailable, reason: "servicesDisabled"); return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if navigationActive { beginNavigationBackgroundActivity() }
            manager.startUpdatingLocation()
            if navigationActive, applicationActive, manager.accuracyAuthorization == .reducedAccuracy,
               !requestedPrecision {
                requestedPrecision = true
                manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "Navigation")
            }
            record(manager.accuracyAuthorization == .reducedAccuracy ? "reducedAccuracy" : "updating")
        case .notDetermined:
            manager.stopUpdatingLocation()
            manager.allowsBackgroundLocationUpdates = false
            manager.showsBackgroundLocationIndicator = false
            backgroundActivitySession?.invalidate()
            backgroundActivitySession = nil
            record("awaitingPermission")
            if applicationActive { manager.requestWhenInUseAuthorization() }
        case .restricted, .denied: fail(Error.permissionDenied, reason: "permissionDenied")
        @unknown default: fail(Error.unavailable, reason: "unknownAuthorization")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard prewarming || navigationActive else { return }
        for location in locations {
            rawFixCount += 1
            let age = Date().timeIntervalSince(location.timestamp)
            guard location.horizontalAccuracy.isFinite, location.horizontalAccuracy >= 0,
                  (-1...5).contains(age),
                  cachedLocation == nil || location.timestamp >= cachedLocation!.timestamp else {
                record("fixRejected")
                continue
            }
            cachedLocation = location
            if location.horizontalAccuracy <= 25 { acceptedFixCount += 1 }
            continuation?.yield(location)
            record(location.horizontalAccuracy <= 25 ? "fix" : "poorAccuracy")
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Swift.Error) {
        guard prewarming || navigationActive else { return }
        let code = error as NSError
        if code.domain == kCLErrorDomain, code.code == CLError.Code.locationUnknown.rawValue {
            lastError = "locationUnknown"
            record("locationUnknown")
            return
        }
        fail(error, reason: "locationError:\(code.code)")
    }

    private func fail(_ error: Swift.Error, reason: String) {
        lastError = reason
        let ended = continuation
        continuation = nil
        stop(reason: reason)
        manager.stopUpdatingLocation()
        ended?.finish(throwing: error)
    }

    private func record(_ event: String) {
        lastEvent = event
        onHealthChange?()
    }

    var needsSettings: Bool {
        servicesAvailable == false || manager.authorizationStatus == .denied ||
            manager.authorizationStatus == .restricted || manager.accuracyAuthorization == .reducedAccuracy
    }

    var healthText: String {
        if servicesAvailable == false { return "Dịch vụ vị trí đang tắt. Mở Cài đặt để bật." }
        switch manager.authorizationStatus {
        case .denied, .restricted: return "Chưa được phép truy cập vị trí. Kiểm tra Cài đặt."
        case .notDetermined: return "Chờ cấp quyền vị trí khi bắt đầu điều hướng."
        default: break
        }
        if manager.accuracyAuthorization == .reducedAccuracy { return "Vị trí gần đúng. Bật Vị trí chính xác để điều hướng." }
        guard let cachedLocation else { return "Đã cấp quyền vị trí chính xác; đang chờ GPS." }
        return "GPS \(rawFixCount) • ±\(Int(cachedLocation.horizontalAccuracy)) m • \(max(0, Int(Date().timeIntervalSince(cachedLocation.timestamp)))) giây trước • \(navigationActive ? "điều hướng" : prewarming ? "chuẩn bị" : "đã dừng")"
    }

    var diagnostic: String {
        "session=\(generation) auth=\(authorizationName) precise=\(manager.accuracyAuthorization == .fullAccuracy) services=\(servicesAvailable.map(String.init) ?? "checking") " +
        "raw=\(rawFixCount) accepted=\(acceptedFixCount) bg=\(manager.allowsBackgroundLocationUpdates) error=\(lastError) event=\(lastEvent)"
    }

    private var authorizationName: String {
        switch manager.authorizationStatus {
        case .authorizedAlways: "always"
        case .authorizedWhenInUse: "whenInUse"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "notDetermined"
        @unknown default: "unknown"
        }
    }

    private func beginNavigationBackgroundActivity() {
        guard navigationActive else { return }
        if backgroundActivitySession == nil { backgroundActivitySession = makeBackgroundActivity() }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
    }
}
