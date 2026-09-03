import CoreLocation
import XCTest
@testable import BlueBandMap

@MainActor
final class ForegroundLocationClientTests: XCTestCase {
    func testServiceAvailabilityProbeDoesNotBlockMainActorOrRepeatForHealthReads() async {
        let manager = TestLocationManager()
        let probeFinished = expectation(description: "background service probe")
        // CLLocationManager may deliver its initial authorization callback after init.
        // That is an allowed second lifecycle probe, independent of health reads below.
        probeFinished.assertForOverFulfill = false
        let client = ForegroundLocationClient(manager: manager, makeBackgroundActivity: { nil }, servicesEnabled: {
            XCTAssertFalse(Thread.isMainThread, "Core Location's global service query must not block GPS/UI")
            probeFinished.fulfill()
            return true
        })
        client.applicationActive(true)
        await fulfillment(of: [probeFinished], timeout: 2)
        for _ in 0..<100 {
            _ = client.healthText
            _ = client.needsSettings
            _ = client.diagnostic
        }
        XCTAssertFalse(manager.updating, "a health probe without a navigation owner cannot start GPS")
    }

    func testTemporaryGPSFailureStillDeliversTheNextFix() async throws {
        let manager = TestLocationManager()
        let client = makeClient(manager)
        var iterator = client.locations().makeAsyncIterator()
        client.locationManager(manager, didFailWithError: NSError(domain: kCLErrorDomain, code: 0))
        let fix = CLLocation(latitude: 21, longitude: 106)
        client.locationManager(manager, didUpdateLocations: [fix])
        let received = try await iterator.next()
        XCTAssertEqual(received, fix)
        XCTAssertTrue(manager.backgroundEnabled)
        client.stop()
    }

    func testOldTerminationCannotStopNewSession() async throws {
        let manager = TestLocationManager()
        let client = makeClient(manager)
        let previous = client.locations()
        client.stop()
        let current = client.locations()
        for _ in 0..<50 { await Task.yield() }
        XCTAssertTrue(manager.updating)
        XCTAssertTrue(manager.backgroundEnabled)
        let fix = CLLocation(latitude: 21, longitude: 106)
        client.locationManager(manager, didUpdateLocations: [fix])
        client.stop()
        var iterator = current.makeAsyncIterator()
        let received = try await iterator.next()
        XCTAssertEqual(received, fix)
        withExtendedLifetime(previous) {}
    }

    func testDeniedTerminatesAndIdleAuthorizationDoesNotStartGPS() async {
        let manager = TestLocationManager()
        let client = makeClient(manager)
        client.locationManagerDidChangeAuthorization(manager)
        XCTAssertFalse(manager.updating)
        var iterator = client.locations().makeAsyncIterator()
        manager.authorization = .denied
        client.locationManagerDidChangeAuthorization(manager)
        do {
            _ = try await iterator.next()
            XCTFail("Denied location must terminate with an actionable error")
        } catch {
            XCTAssertTrue(client.needsSettings)
            XCTAssertFalse(manager.updating)
            XCTAssertFalse(manager.backgroundEnabled)
        }
        client.stop()
        XCTAssertTrue(client.diagnostic.contains("error=permissionDenied"))
    }

    func testReducedAccuracyAndExpiredAllowOnce() {
        let manager = TestLocationManager()
        let client = makeClient(manager)
        manager.authorization = .notDetermined
        client.applicationActive(false)
        let stream = client.locations()
        XCTAssertEqual(manager.permissionRequests, 0)
        client.applicationActive(true)
        XCTAssertEqual(manager.permissionRequests, 1)
        manager.authorization = .authorizedWhenInUse
        manager.precision = .reducedAccuracy
        client.locationManagerDidChangeAuthorization(manager)
        client.locationManagerDidChangeAuthorization(manager)
        XCTAssertEqual(manager.precisionRequests, 1)
        XCTAssertTrue(client.needsSettings)
        client.applicationActive(false)
        manager.authorization = .notDetermined
        client.locationManagerDidChangeAuthorization(manager)
        XCTAssertFalse(manager.updating)
        XCTAssertFalse(manager.backgroundEnabled)
        client.stop()
        withExtendedLifetime(stream) {}
    }

    func testStaleFixIsCountedButNeverPublishedAsCurrentGPS() async throws {
        let manager = TestLocationManager()
        let client = makeClient(manager)
        let stream = client.locations()
        let stale = CLLocation(coordinate: .init(latitude: 21, longitude: 106), altitude: 0,
                               horizontalAccuracy: 5, verticalAccuracy: 5,
                               timestamp: Date().addingTimeInterval(-60))
        client.locationManager(manager, didUpdateLocations: [stale])
        client.stop()
        var iterator = stream.makeAsyncIterator()
        let received = try await iterator.next()
        XCTAssertNil(received)
        XCTAssertEqual(client.rawFixCount, 1)
        XCTAssertEqual(client.acceptedFixCount, 0)
    }

    private func makeClient(_ manager: TestLocationManager) -> ForegroundLocationClient {
        ForegroundLocationClient(manager: manager, makeBackgroundActivity: { nil }, servicesEnabled: { true })
    }
}

final class TestLocationManager: CLLocationManager {
    var authorization: CLAuthorizationStatus = .authorizedWhenInUse
    var precision: CLAccuracyAuthorization = .fullAccuracy
    var updating = false
    var backgroundEnabled = false
    var indicator = false
    var permissionRequests = 0
    var precisionRequests = 0
    override var authorizationStatus: CLAuthorizationStatus { authorization }
    override var accuracyAuthorization: CLAccuracyAuthorization { precision }
    override var allowsBackgroundLocationUpdates: Bool {
        get { backgroundEnabled }
        set { backgroundEnabled = newValue }
    }
    override var showsBackgroundLocationIndicator: Bool {
        get { indicator }
        set { indicator = newValue }
    }
    override func startUpdatingLocation() { updating = true }
    override func stopUpdatingLocation() { updating = false }
    override func requestWhenInUseAuthorization() { permissionRequests += 1 }
    override func requestTemporaryFullAccuracyAuthorization(withPurposeKey purposeKey: String) { precisionRequests += 1 }
}
