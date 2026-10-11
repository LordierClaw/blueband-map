import BlueBandMapCore
import CoreLocation
import XCTest
@testable import BlueBandMap

@MainActor
final class NavigationReplayTests: XCTestCase {
    func testLatencyFullFlowHasMovementZoomDrainAndBoundedAutomaticCompletion() async throws {
        let clock = ReplayClock()
        let replay = NavigationReplay(now: { clock.time }, date: { clock.date }, sleep: { try await clock.sleep($0) })
        defer { replay.stop(); clock.finishSleeps() }
        var phases: [String] = [], fixes: [CLLocation] = []
        var finished = 0
        replay.onPhase = { phases.append($0) }
        replay.onFixObserved = { fixes.append($0) }
        replay.onFinished = { finished += 1 }
        replay.start(at: point(0, 0))
        replay.follow(route: route([point(0, 0), point(0, 0.01), point(0.01, 0.01), point(0.01, 0)]))
        await settle()
        for _ in 0..<280 { await clock.advance(by: 1) }
        XCTAssertTrue(phases.contains("cachedMovement"))
        XCTAssertTrue(phases.contains("coverage"))
        XCTAssertTrue(phases.contains("zoomOut"))
        XCTAssertTrue(phases.contains("zoomIn"))
        XCTAssertTrue(phases.contains("drain"))
        let atDrain = fixes.count
        for _ in 0..<20 { await clock.advance(by: 1) }
        XCTAssertEqual(fixes.count, atDrain, "drain must stop producers")
        XCTAssertEqual(finished, 1)
        XCTAssertNil(replay.recentLocation())
    }

    func testStartProvidesStationaryFreshFixWithoutDeviceGPS() async throws {
        let clock = ReplayClock()
        let replay = makeReplay(clock)
        defer { replay.stop(); clock.finishSleeps() }
        var observed: [CLLocation] = []
        replay.onFixObserved = { observed.append($0) }
        replay.start()
        let seed = try XCTUnwrap(replay.recentLocation())
        XCTAssertEqual(seed.coordinate.latitude, 10.759157, accuracy: 0.0000001)
        XCTAssertEqual(seed.coordinate.longitude, 106.675859, accuracy: 0.0000001)
        XCTAssertEqual(seed.speed, 0)
        XCTAssertEqual(seed.horizontalAccuracy, 5)
        XCTAssertEqual(seed.timestamp, clock.date)
        XCTAssertEqual(observed.count, 1)
        var iterator = replay.locations().makeAsyncIterator()
        let streamed = try await iterator.next()
        XCTAssertEqual(streamed, seed)
        replay.stop()
    }

    func testMovementInterpolatesAtTenMetersPerSecondAndTurnsPastDuplicateVertices() async throws {
        let clock = ReplayClock()
        let replay = makeReplay(clock)
        defer { replay.stop(); clock.finishSleeps() }
        var fixes: [CLLocation] = []
        var phases: [String] = []
        replay.onFixObserved = { fixes.append($0) }
        replay.onPhase = { phases.append($0) }
        // About 11.12 m east, then 111.2 m north. Duplicate vertices are harmless.
        replay.start(at: point(0, 0))
        replay.follow(route: route([point(0, 0), point(0, 0), point(0, 0.0001),
                                    point(0, 0.0001), point(0.001, 0.0001)]))
        await settle()
        await clock.advance(by: 1)
        XCTAssertEqual(fixes.count, 2)
        let east = try XCTUnwrap(fixes.last)
        XCTAssertEqual(east.coordinate.latitude, 0, accuracy: 0.000001)
        XCTAssertEqual(east.coordinate.longitude, 0.00008993, accuracy: 0.000001)
        XCTAssertEqual(east.course, 90, accuracy: 0.1)
        XCTAssertEqual(east.speed, 10)
        XCTAssertEqual(east.timestamp, clock.date)
        await clock.advance(by: 1)
        let north = try XCTUnwrap(fixes.last)
        XCTAssertEqual(north.coordinate.longitude, 0.0001, accuracy: 0.000001)
        XCTAssertEqual(north.coordinate.latitude, 0.00007986, accuracy: 0.000001)
        XCTAssertEqual(north.course, 0, accuracy: 0.1)
        XCTAssertTrue(phases.contains("movement"))
        XCTAssertTrue(phases.contains("courseChange"))
        replay.stop()
    }

    func testDelayedWakeEmitsOneCurrentFixWithoutBurstingMissedTicks() async throws {
        let clock = ReplayClock()
        let replay = makeReplay(clock)
        defer { replay.stop(); clock.finishSleeps() }
        var fixes: [CLLocation] = []
        replay.onFixObserved = { fixes.append($0) }
        replay.start(at: point(0, 0))
        replay.follow(route: route([point(0, 0), point(0, 0.01)]))
        await settle()
        await clock.advance(by: 12)
        XCTAssertEqual(fixes.count, 2, "delayed wake skips eleven stale samples")
        let current = try XCTUnwrap(fixes.last)
        XCTAssertEqual(current.coordinate.longitude, 0.00107919, accuracy: 0.000002)
        XCTAssertEqual(current.timestamp, clock.date)
        await clock.advance(by: 0.5)
        XCTAssertEqual(fixes.count, 2)
        await clock.advance(by: 0.5)
        XCTAssertEqual(fixes.count, 3)
        replay.stop()
    }

    func testStopAndRestartContainsOldSleeperAndOldStreamTermination() async throws {
        let clock = ReplayClock()
        let replay = makeReplay(clock)
        defer { replay.stop(); clock.finishSleeps() }
        var fixes: [CLLocation] = []
        replay.onFixObserved = { fixes.append($0) }
        replay.start(at: point(0, 0))
        let oldStream = replay.locations()
        replay.follow(route: route([point(0, 0), point(0, 0.01)]))
        await settle()
        replay.stop()
        XCTAssertNil(replay.recentLocation())
        replay.start(at: point(1, 1))
        let currentStream = replay.locations()
        replay.follow(route: route([point(1, 1), point(1.01, 1)]))
        await settle()
        await clock.advance(by: 1)
        XCTAssertEqual(fixes.count, 3, "only the successor may emit after old sleeps finish")
        XCTAssertEqual(try XCTUnwrap(fixes.last).coordinate.longitude, 1, accuracy: 0.000001)
        replay.stop()
        await clock.advance(by: 20)
        XCTAssertEqual(fixes.count, 3)
        withExtendedLifetime((oldStream, currentStream)) {}
    }

    func testArrivalEmitsExactEndpointAndFinishesOnce() async throws {
        let clock = ReplayClock()
        let replay = makeReplay(clock)
        defer { replay.stop(); clock.finishSleeps() }
        var fixes: [CLLocation] = []
        var phases: [String] = []
        var finished = 0
        replay.onFixObserved = { fixes.append($0) }
        replay.onPhase = { phases.append($0) }
        replay.onFinished = { finished += 1 }
        replay.start(at: point(0, 0))
        replay.follow(route: route([point(0, 0), point(0, 0.0001)]))
        await settle()
        await clock.advance(by: 1)
        await clock.advance(by: 1)
        XCTAssertEqual(fixes.count, 3)
        XCTAssertEqual(try XCTUnwrap(fixes.last).coordinate.longitude, 0.0001, accuracy: 0.0000001)
        XCTAssertEqual(try XCTUnwrap(fixes.last).speed, 0)
        XCTAssertTrue(phases.contains("arrival"))
        XCTAssertEqual(finished, 1)
        await clock.advance(by: 10)
        XCTAssertEqual(fixes.count, 3)
        XCTAssertEqual(finished, 1)
    }

    func testTimeoutBoundsRouteAndWaitingForRouteByTenMinutes() async {
        for followsRoute in [false, true] {
            let clock = ReplayClock()
            let replay = makeReplay(clock)
            defer { replay.stop(); clock.finishSleeps() }
            var phases: [String] = []
            var fixes = 0
            var finished = 0
            replay.onPhase = { phases.append($0) }
            replay.onFixObserved = { _ in fixes += 1 }
            replay.onFinished = { finished += 1 }
            replay.start(at: point(0, 0))
            if followsRoute {
                replay.follow(route: route((0...100).map { point(0, Double($0) * 0.001) }))
            }
            await settle()
            await clock.advance(by: 601)
            XCTAssertTrue(phases.contains("timeout"))
            XCTAssertEqual(finished, 1)
            XCTAssertEqual(fixes, 1, "expired playback does not emit a post-deadline fix")
            await clock.advance(by: 60)
            XCTAssertEqual(finished, 1)
        }
    }

    func testInvalidGeometryFailsStreamWithoutStartingMovement() async throws {
        let invalid: [[GeoPoint]] = [[], [point(0, 0)], [point(0, 0), point(0, 0)],
            [point(0, 0), point(.nan, 0)], [point(0, 0), point(0, .infinity)],
            [point(0, 0), point(91, 0)], [point(0, 0), point(0, 181)],
            [point(0, 0), point(20, 20)], Array(repeating: point(0, 0), count: 4_097)]
        for points in invalid {
            let clock = ReplayClock()
            let replay = makeReplay(clock)
            defer { replay.stop(); clock.finishSleeps() }
            var finished = 0
            replay.onFinished = { finished += 1 }
            replay.start(at: point(0, 0))
            var iterator = replay.locations().makeAsyncIterator()
            _ = try await iterator.next()
            replay.follow(route: route(points))
            do {
                _ = try await iterator.next()
                XCTFail("invalid geometry must fail the source")
            } catch {
                XCTAssertEqual(error as? NavigationReplay.Error, .invalidRoute)
            }
            XCTAssertEqual(finished, 0, "source errors are handled by the stream consumer")
            replay.stop()
        }
    }

    func testMovementCallbackRestartCannotPublishOldPhaseIntoSuccessor() async throws {
        let clock = ReplayClock()
        let replay = makeReplay(clock)
        defer { replay.stop(); clock.finishSleeps() }
        var phases: [String] = []
        replay.start(at: point(0, 0))
        replay.follow(route: route([point(0, 0), point(0, 0.01)]))
        replay.onPhase = { phases.append($0) }
        replay.onFixObserved = { fix in
            guard fix.speed > 0 else { return }
            replay.stop()
            replay.start(at: self.point(1, 1))
            phases.removeAll()
        }
        await settle()
        await clock.advance(by: 1)
        XCTAssertEqual(try XCTUnwrap(replay.recentLocation()).coordinate.latitude, 1)
        XCTAssertTrue(phases.isEmpty, "retired emission cannot report movement for the new run")
        replay.stop()
    }

    private func point(_ latitude: Double, _ longitude: Double) -> GeoPoint {
        GeoPoint(latitude: latitude, longitude: longitude)
    }

    private func route(_ points: [GeoPoint]) -> RoutePlan {
        RoutePlan(points: points, instructions: [], distanceMeters: 0)
    }

    private func makeReplay(_ clock: ReplayClock) -> NavigationReplay {
        NavigationReplay(now: { clock.time }, date: { clock.date }, sleep: { try await clock.sleep($0) })
    }

    private func settle() async {
        for _ in 0..<30 { await Task.yield() }
    }
}

@MainActor
private final class ReplayClock {
    var time: TimeInterval = 0
    var date: Date { Date(timeIntervalSince1970: 1_800_000_000 + time) }
    private var sleepers: [(deadline: TimeInterval, continuation: CheckedContinuation<Void, Swift.Error>)] = []

    func sleep(_ seconds: TimeInterval) async throws {
        // Deliberately allow cancelled sleeps to return: the source must check ownership.
        try await withCheckedThrowingContinuation { continuation in
            sleepers.append((time + seconds, continuation))
        }
    }

    func advance(by seconds: TimeInterval) async {
        time += seconds
        let due = sleepers.filter { $0.deadline <= time }
        sleepers.removeAll { $0.deadline <= time }
        for sleeper in due { sleeper.continuation.resume() }
        for _ in 0..<30 { await Task.yield() }
    }

    func finishSleeps() {
        let pending = sleepers
        sleepers.removeAll()
        for sleeper in pending { sleeper.continuation.resume() }
    }
}
