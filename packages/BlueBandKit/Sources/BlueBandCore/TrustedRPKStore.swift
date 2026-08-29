import Foundation

public protocol TrustedRPKStore: Sendable {
    func trustedRPKFingerprint() async throws -> Data?
    func saveTrustedRPKFingerprint(_ fingerprint: Data) async throws
    func resetTrustedRPKFingerprint() async throws
}

public protocol BlueBandClock: Sendable {
    func sleep(for duration: Duration) async throws
}

public struct ContinuousBlueBandClock: BlueBandClock {
    public init() {}
    public func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }
}
