import Foundation

public struct BandCandidate: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let rssi: Int

    public init(id: UUID, name: String, rssi: Int) {
        self.id = id
        self.name = name
        self.rssi = rssi
    }
}

public enum SessionState: String, Equatable, Sendable {
    case idle
    case scanning
    case connecting
    case discoveringGatt
    case configuringSpp
    case authenticating
    case readingDeviceProof
    case waitingForRpk
    case applicationReady
    case disconnecting
}

public protocol BandCentralProtocol: Sendable {
    func scan() async -> AsyncThrowingStream<[BandCandidate], Swift.Error>
    func stopScan() async
    func connect(id: UUID) async throws -> any BandLink
}

public struct BandSnapshot: Equatable, Sendable {
    public var batteryLevel: UInt8?
    public var batteryState: UInt32?
    public var model: String?
    public var firmware: String?

    public init(batteryLevel: UInt8? = nil, batteryState: UInt32? = nil, model: String? = nil, firmware: String? = nil) {
        self.batteryLevel = batteryLevel
        self.batteryState = batteryState
        self.model = model
        self.firmware = firmware
    }
}

public enum BandSessionError: Swift.Error, Equatable {
    case alreadyConnected
    case notConnected
    case disconnected
    case rejected(status: UInt32)
    case timeout
}
