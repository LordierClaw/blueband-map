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

    init(
        now: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        date: @escaping @MainActor () -> Date = { Date() },
        sleep: @escaping @MainActor (TimeInterval) async throws -> Void = {
            try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
        }
    ) {}

    func start(at point: GeoPoint = NavigationReplay.origin) {}
    func locations() -> AsyncThrowingStream<CLLocation, Swift.Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func recentLocation() -> CLLocation? { nil }
    func follow(route: RoutePlan) {}
    func stop() {}
}
