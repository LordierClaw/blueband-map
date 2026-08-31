import CoreLocation
import Foundation
import BlueBandMapCore

@MainActor
final class ForegroundLocationClient: NSObject, CLLocationManagerDelegate {
    enum Error: Swift.Error { case permissionDenied, unavailable }

    private let manager = CLLocationManager()
    private var continuation: AsyncThrowingStream<CLLocation, Swift.Error>.Continuation?
    private var cachedLocation: CLLocation?
    private var prewarming = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = 1
        manager.pausesLocationUpdatesAutomatically = false
    }

    func locations() -> AsyncThrowingStream<CLLocation, Swift.Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            self.continuation?.finish()
            self.continuation = continuation
            if let recentLocation = self.recentLocation() { continuation.yield(recentLocation) }
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor in self?.stop() }
            }
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .restricted, .denied: continuation.finish(throwing: Error.permissionDenied)
            default: manager.startUpdatingLocation()
            }
        }
    }

    func startPrewarming() {
        prewarming = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.startUpdatingLocation()
        default: break
        }
    }

    func stopPrewarming() {
        prewarming = false
        if continuation == nil { manager.stopUpdatingLocation() }
    }

    func recentLocation(now: Date = Date()) -> CLLocation? {
        guard let cachedLocation,
              ReusableLocationPolicy.isReusable(
                horizontalAccuracyMeters: cachedLocation.horizontalAccuracy,
                ageSeconds: now.timeIntervalSince(cachedLocation.timestamp)
              ) else { return nil }
        return cachedLocation
    }

    func stop() {
        continuation?.finish()
        continuation = nil
        if !prewarming { manager.stopUpdatingLocation() }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.startUpdatingLocation()
        case .restricted, .denied: continuation?.finish(throwing: Error.permissionDenied)
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations where location.horizontalAccuracy >= 0 {
            if cachedLocation == nil || location.timestamp >= cachedLocation!.timestamp { cachedLocation = location }
            continuation?.yield(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Swift.Error) {
        continuation?.finish(throwing: error)
    }
}
