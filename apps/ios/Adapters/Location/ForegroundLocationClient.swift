import CoreLocation
import Foundation

@MainActor
final class ForegroundLocationClient: NSObject, CLLocationManagerDelegate {
    enum Error: Swift.Error { case permissionDenied, unavailable }

    private let manager = CLLocationManager()
    private var continuation: AsyncThrowingStream<CLLocation, Swift.Error>.Continuation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = 1
        manager.pausesLocationUpdatesAutomatically = false
    }

    func locations() -> AsyncThrowingStream<CLLocation, Swift.Error> {
        AsyncThrowingStream { continuation in
            self.continuation?.finish()
            self.continuation = continuation
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

    func stop() {
        manager.stopUpdatingLocation()
        continuation?.finish()
        continuation = nil
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
            continuation?.yield(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Swift.Error) {
        continuation?.finish(throwing: error)
    }
}
