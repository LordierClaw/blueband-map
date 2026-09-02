import Foundation
import Dispatch

// Linux test boundary only. The production adapter below is compiled unchanged,
// except for its Apple imports. This is not a simulation of iOS permissions/GPS.
enum CLAuthorizationStatus { case notDetermined, restricted, denied, authorizedAlways, authorizedWhenInUse }
enum CLAccuracyAuthorization { case fullAccuracy, reducedAccuracy }
enum CLActivityType { case automotiveNavigation }
let kCLLocationAccuracyBestForNavigation = -2.0
let kCLErrorDomain = "kCLErrorDomain"
enum CLError { enum Code: Int { case locationUnknown = 0, denied = 1, network = 2 } }
protocol CLLocationManagerDelegate: AnyObject {}
@MainActor class CLLocationManager {
    static var latest: CLLocationManager?
    static var servicesEnabled = true
    static func locationServicesEnabled() -> Bool { servicesEnabled }
    weak var delegate: CLLocationManagerDelegate?
    var authorizationStatus = CLAuthorizationStatus.authorizedWhenInUse
    var accuracyAuthorization = CLAccuracyAuthorization.fullAccuracy
    var desiredAccuracy = 0.0
    var activityType = CLActivityType.automotiveNavigation
    var distanceFilter = 0.0
    var pausesLocationUpdatesAutomatically = true
    var allowsBackgroundLocationUpdates = false
    var showsBackgroundLocationIndicator = false
    var updating = false
    var permissionRequests = 0
    var precisionRequests = 0
    init() { Self.latest = self }
    func requestWhenInUseAuthorization() { permissionRequests += 1 }
    func requestTemporaryFullAccuracyAuthorization(withPurposeKey: String) { precisionRequests += 1 }
    func startUpdatingLocation() { updating = true }
    func stopUpdatingLocation() { updating = false }
}
final class CLLocation: @unchecked Sendable {
    let timestamp: Date
    let horizontalAccuracy: Double
    init(timestamp: Date = Date(), accuracy: Double = 5) {
        self.timestamp = timestamp
        self.horizontalAccuracy = accuracy
    }
}
final class CLBackgroundActivitySession {
    func invalidate() {}
}
enum ReusableLocationPolicy {
    static func isReusable(horizontalAccuracyMeters: Double, ageSeconds: Double) -> Bool {
        (0...25).contains(horizontalAccuracyMeters) && (0...10).contains(ageSeconds)
    }
}
