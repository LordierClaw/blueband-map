final class LocationServiceProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var reads: Int { lock.withLock { count } }
    func read() -> Bool { lock.withLock { count += 1 }; return true }
}

Task { @MainActor in
    var failures = 0
    func check(_ passed: Bool, _ name: String) {
        print("\(passed ? "PASS" : "FAIL") \(name)")
        if !passed { failures += 1 }
    }

    let client = ForegroundLocationClient()
    let manager = CLLocationManager.latest!
    var iterator = client.locations().makeAsyncIterator()
    client.locationManager(manager, didFailWithError: NSError(domain: kCLErrorDomain, code: 0))
    let fix = CLLocation()
    client.locationManager(manager, didUpdateLocations: [fix])
    do {
        let received = try await iterator.next()
        check(received === fix, "temporary locationUnknown recovers on the next fix")
    } catch { check(false, "temporary locationUnknown must not terminate the stream") }
    await Task.yield()
    check(manager.allowsBackgroundLocationUpdates, "temporary error keeps background activity")
    client.stop()

    let restart = ForegroundLocationClient()
    let restartManager = CLLocationManager.latest!
    let old = restart.locations()
    restart.stop()
    let current = restart.locations()
    // Drain the queued old onTermination task; delivery must still reach current.
    try? await Task.sleep(for: .milliseconds(20))
    check(restartManager.updating && restartManager.allowsBackgroundLocationUpdates,
          "old termination cannot stop a new navigation session")
    restart.locationManager(restartManager, didUpdateLocations: [fix])
    restart.stop()
    var currentIterator = current.makeAsyncIterator()
    let received = try? await currentIterator.next()
    check(received === fix, "new session receives a fix after old cleanup")
    withExtendedLifetime(old) {}

    let idle = ForegroundLocationClient()
    let idleManager = CLLocationManager.latest!
    idle.locationManagerDidChangeAuthorization(idleManager)
    check(!idleManager.updating, "authorization callback without an owner leaves GPS off")
    let prewarm = idle.locations()
    idle.startPrewarming()
    idle.stopPrewarming()
    check(idleManager.updating, "leaving prewarm does not stop active navigation")
    idle.stop()
    check(!idleManager.updating && !idleManager.allowsBackgroundLocationUpdates,
          "explicit stop releases GPS and background ownership")
    withExtendedLifetime(prewarm) {}

    let permissions = ForegroundLocationClient()
    let permissionsManager = CLLocationManager.latest!
    permissionsManager.authorizationStatus = .notDetermined
    permissions.applicationActive(false)
    let permissionStream = permissions.locations()
    check(permissionsManager.permissionRequests == 0, "no permission prompt while backgrounded")
    permissions.applicationActive(true)
    check(permissionsManager.permissionRequests == 1, "request permission after returning active")
    permissionsManager.authorizationStatus = .authorizedWhenInUse
    permissionsManager.accuracyAuthorization = .reducedAccuracy
    permissions.locationManagerDidChangeAuthorization(permissionsManager)
    permissions.locationManagerDidChangeAuthorization(permissionsManager)
    check(permissionsManager.precisionRequests == 1 && permissions.needsSettings,
          "reduced accuracy is visible and requests precision once")
    permissionsManager.authorizationStatus = .notDetermined
    permissions.applicationActive(false)
    permissions.locationManagerDidChangeAuthorization(permissionsManager)
    check(!permissionsManager.allowsBackgroundLocationUpdates && !permissionsManager.updating,
          "expired Allow Once releases previously authorized services")
    permissions.stop()
    withExtendedLifetime(permissionStream) {}

    let revoked = ForegroundLocationClient()
    let revokedManager = CLLocationManager.latest!
    let revokedStream = revoked.locations()
    revoked.locationManager(revokedManager, didUpdateLocations: [CLLocation()])
    revokedManager.authorizationStatus = .denied
    check(revoked.recentLocation() == nil, "cached fix cannot bypass revoked permission")
    revoked.stop()
    withExtendedLifetime(revokedStream) {}

    let failed = ForegroundLocationClient()
    let failedManager = CLLocationManager.latest!
    let failedStream = failed.locations()
    failed.locationManager(failedManager, didFailWithError: NSError(domain: kCLErrorDomain, code: 42))
    failed.stop()
    check(failed.diagnostic.contains("error=locationError:42"),
          "normal cleanup must not erase the last location error from exported health")
    withExtendedLifetime(failedStream) {}

    let probe = LocationServiceProbe()
    let health = ForegroundLocationClient(manager: CLLocationManager(), servicesEnabled: { probe.read() })
    health.applicationActive(true)
    try? await Task.sleep(for: .milliseconds(20))
    let readsBeforeHealth = probe.reads
    for _ in 0..<100 {
        _ = health.healthText
        _ = health.needsSettings
        _ = health.diagnostic
    }
    check(probe.reads == readsBeforeHealth,
          "UI and GPS diagnostics read cached service health without synchronous system probes")
    exit(failures == 0 ? 0 : 1)
}
dispatchMain()
