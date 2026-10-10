import BlueBandMapCore
import CoreLocation
import Foundation

@MainActor
final class NavigationReplay {
    enum Error: Swift.Error, Equatable { case invalidRoute }
    static let origin = GeoPoint(latitude: 10.759157, longitude: 106.675859)
    static let destination = GeoPoint(latitude: 10.762622, longitude: 106.660172)
    static let maximumDurationSeconds: TimeInterval = 600

    var onFixObserved: ((CLLocation) -> Void)?
    var onPhase: ((String) -> Void)?
    var onFinished: (() -> Void)?
    private(set) var lastScheduledElapsedSeconds: TimeInterval = 0
    private(set) var lastEmittedElapsedSeconds: TimeInterval = 0

    private struct Segment {
        let start: GeoPoint
        let end: GeoPoint
        let meters: Double
        let course: Double
    }
    private let now: @MainActor () -> TimeInterval
    private let date: @MainActor () -> Date
    private let sleep: @MainActor (TimeInterval) async throws -> Void
    private var task: Task<Void, Never>?
    private var continuation: AsyncThrowingStream<CLLocation, Swift.Error>.Continuation?
    private var cachedLocation: CLLocation?
    private var terminalError: Swift.Error?
    private var generation = 0
    private var subscription = 0
    private var active = false
    private var startedAt: TimeInterval = 0
    private var routeStartedAt: TimeInterval?
    private var segments: [Segment] = []
    private var totalMeters = 0.0
    private var previousCourse: Double?

    init(
        now: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        date: @escaping @MainActor () -> Date = { Date() },
        sleep: @escaping @MainActor (TimeInterval) async throws -> Void = {
            try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
        }
    ) {
        self.now = now
        self.date = date
        self.sleep = sleep
    }

    func start(at point: GeoPoint = NavigationReplay.origin) {
        stop()
        active = true
        startedAt = now()
        let owner = generation
        guard Self.valid(point) else {
            end(phase: "invalidRoute", error: Error.invalidRoute)
            return
        }
        onPhase?("startup")
        guard active, generation == owner else { return }
        emit(point, course: 0, speed: 0, scheduled: 0, owner: owner)
        guard active, generation == owner else { return }
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.run(owner: owner)
        }
    }

    func locations() -> AsyncThrowingStream<CLLocation, Swift.Error> {
        subscription += 1
        let subscriber = subscription
        let owner = generation
        continuation?.finish()
        continuation = nil
        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            guard active else { continuation.finish(throwing: terminalError); return }
            self.continuation = continuation
            if let cachedLocation { continuation.yield(cachedLocation) }
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor in
                    guard let self, self.active, self.generation == owner,
                          self.subscription == subscriber else { return }
                    self.stop()
                }
            }
        }
    }

    func recentLocation() -> CLLocation? { active ? cachedLocation : nil }

    func follow(route: RoutePlan) {
        guard active else { return }
        guard (2...4_096).contains(route.points.count), route.points.allSatisfy({ Self.valid($0) }) else {
            end(phase: "invalidRoute", error: Error.invalidRoute)
            return
        }
        var parsed: [Segment] = []
        for (start, end) in zip(route.points, route.points.dropFirst()) {
            let meters = Self.distance(start, end)
            // Bound malformed/disconnected geometry before any trajectory reaches navigation.
            guard meters.isFinite, meters <= 10_000 else {
                self.end(phase: "invalidRoute", error: Error.invalidRoute)
                return
            }
            if meters > 0 {
                parsed.append(Segment(start: start, end: end, meters: meters, course: Self.bearing(start, end)))
            }
        }
        guard !parsed.isEmpty else { end(phase: "invalidRoute", error: Error.invalidRoute); return }
        segments = parsed
        totalMeters = parsed.reduce(0) { $0 + $1.meters }
        routeStartedAt = now()
        previousCourse = nil
    }

    func stop() {
        generation += 1
        active = false
        task?.cancel()
        task = nil
        let ended = continuation
        continuation = nil
        cachedLocation = nil
        terminalError = nil
        segments = []
        routeStartedAt = nil
        previousCourse = nil
        lastScheduledElapsedSeconds = 0
        lastEmittedElapsedSeconds = 0
        ended?.finish()
    }

    private func run(owner: Int) async {
        while active, generation == owner, !Task.isCancelled {
            let elapsed = now() - startedAt
            let remaining = Self.maximumDurationSeconds - elapsed
            guard remaining > 0 else { end(phase: "timeout"); return }
            let delay = min(1, remaining)
            let scheduled = elapsed + delay
            do { try await sleep(delay) } catch {
                guard active, generation == owner, !Task.isCancelled else { return }
                end(phase: "sourceError", error: error)
                return
            }
            guard active, generation == owner, !Task.isCancelled else { return }
            guard now() - startedAt < Self.maximumDurationSeconds else { end(phase: "timeout"); return }
            guard let routeStartedAt else { continue }
            // Use the actual monotonic wake time and schedule one future tick. Never catch up in a burst.
            let meters = min(totalMeters, max(0, now() - routeStartedAt) * 10)
            var remainingMeters = meters
            var segment = segments[segments.count - 1]
            for candidate in segments {
                segment = candidate
                if remainingMeters <= candidate.meters { break }
                remainingMeters -= candidate.meters
            }
            let fraction = min(1, remainingMeters / segment.meters)
            let point = meters >= totalMeters ? segment.end : GeoPoint(
                latitude: segment.start.latitude + (segment.end.latitude - segment.start.latitude) * fraction,
                longitude: Self.normalizedLongitude(segment.start.longitude +
                    Self.normalizedLongitude(segment.end.longitude - segment.start.longitude) * fraction)
            )
            let priorCourse = previousCourse
            previousCourse = segment.course
            emit(point, course: segment.course, speed: meters >= totalMeters ? 0 : 10,
                 scheduled: scheduled, owner: owner)
            guard active, generation == owner else { return }
            if priorCourse == nil {
                onPhase?("movement")
            } else if abs(Self.normalizedLongitude(segment.course - priorCourse!)) >= 30 {
                onPhase?("courseChange")
            }
            guard active, generation == owner else { return }
            if meters >= totalMeters { end(phase: "arrival"); return }
        }
    }

    private func emit(_ point: GeoPoint, course: Double, speed: Double, scheduled: TimeInterval, owner: Int) {
        let fix = CLLocation(coordinate: .init(latitude: point.latitude, longitude: point.longitude), altitude: 0,
                             horizontalAccuracy: 5, verticalAccuracy: 5, course: course, speed: speed,
                             timestamp: date())
        lastScheduledElapsedSeconds = scheduled
        lastEmittedElapsedSeconds = max(0, now() - startedAt)
        cachedLocation = fix
        onFixObserved?(fix)
        guard active, generation == owner else { return }
        continuation?.yield(fix)
    }

    private func end(phase: String, error: Swift.Error? = nil) {
        guard active else { return }
        generation += 1
        let owner = generation
        active = false
        task?.cancel()
        task = nil
        terminalError = error
        let ended = continuation
        continuation = nil
        ended?.finish(throwing: error)
        onPhase?(phase)
        guard generation == owner else { return }
        if error == nil { onFinished?() }
    }

    private static func valid(_ point: GeoPoint) -> Bool {
        point.latitude.isFinite && point.longitude.isFinite &&
            (-90...90).contains(point.latitude) && (-180...180).contains(point.longitude)
    }

    private static func normalizedLongitude(_ value: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: 360)
        return result > 180 ? result - 360 : result < -180 ? result + 360 : result
    }

    private static func distance(_ start: GeoPoint, _ end: GeoPoint) -> Double {
        let radians = Double.pi / 180
        let latitude = (end.latitude - start.latitude) * radians
        let longitude = normalizedLongitude(end.longitude - start.longitude) * radians
        let h = pow(sin(latitude / 2), 2) + cos(start.latitude * radians) * cos(end.latitude * radians) *
            pow(sin(longitude / 2), 2)
        return 6_371_000 * 2 * asin(sqrt(min(1, max(0, h))))
    }

    private static func bearing(_ start: GeoPoint, _ end: GeoPoint) -> Double {
        let radians = Double.pi / 180
        let longitude = normalizedLongitude(end.longitude - start.longitude) * radians
        let y = sin(longitude) * cos(end.latitude * radians)
        let x = cos(start.latitude * radians) * sin(end.latitude * radians) -
            sin(start.latitude * radians) * cos(end.latitude * radians) * cos(longitude)
        return (atan2(y, x) / radians + 360).truncatingRemainder(dividingBy: 360)
    }
}
