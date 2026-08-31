import BlueBandCore
import Foundation

public struct NavigationUpdate: Equatable, Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidScene, invalidSequence, invalidMarker, invalidHeading, invalidDistance
    }
    public static let topic = "nav.update"

    public let scene: String
    public let seq: Int
    public let x: Int
    public let y: Int
    public let maneuver: NavigationManeuver
    public let headingBucket: Int
    public let distanceMeters: Int
    public let street: String
    public let status: NavigationStatus

    public init(
        scene: String,
        seq: Int,
        x: Int,
        y: Int,
        maneuver: NavigationManeuver,
        headingBucket: Int = 0,
        distanceMeters: Int,
        street: String,
        status: NavigationStatus
    ) throws {
        guard RenderProtocol.isValidIdentifier(scene) else { throw Error.invalidScene }
        guard seq >= 0 else { throw Error.invalidSequence }
        guard (0..<RenderProtocol.viewportWidth).contains(x), (0..<RenderProtocol.viewportHeight).contains(y) else {
            throw Error.invalidMarker
        }
        guard (0..<8).contains(headingBucket) else { throw Error.invalidHeading }
        guard distanceMeters >= 0 else { throw Error.invalidDistance }
        var boundedStreet = street
        while boundedStreet.utf8.count > 48 { boundedStreet.removeLast() }
        self.scene = scene
        self.seq = seq
        self.x = x
        self.y = y
        self.maneuver = maneuver
        self.headingBucket = headingBucket
        self.distanceMeters = distanceMeters
        self.street = boundedStreet
        self.status = status
    }

    public func jsonBody() -> [String: JSONValue] {
        [
            "scene": .string(scene), "seq": .number(Double(seq)),
            "x": .number(Double(x)), "y": .number(Double(y)),
            "heading": .number(Double(headingBucket)),
            "maneuver": .string(maneuver.rawValue), "distanceM": .number(Double(distanceMeters)),
            "street": .string(street), "status": .string(status.rawValue),
        ]
    }
}

public struct NavigationUpdateCoalescer: Sendable {
    private var inFlight = false
    private var pending: NavigationUpdate?
    private var latestByScene: [String: Int] = [:]

    public init() {}

    public mutating func enqueue(_ update: NavigationUpdate) -> NavigationUpdate? {
        guard update.seq > latestByScene[update.scene, default: -1] else { return nil }
        latestByScene[update.scene] = update.seq
        guard inFlight else { inFlight = true; return update }
        pending = update
        return nil
    }

    public mutating func completed() -> NavigationUpdate? {
        if let pending { self.pending = nil; return pending }
        inFlight = false
        return nil
    }

    public mutating func reset() {
        inFlight = false
        pending = nil
        latestByScene.removeAll(keepingCapacity: true)
    }
}
