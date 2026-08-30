import Foundation

public struct ScenePoint: Equatable, Sendable {
    public let x: UInt16
    public let y: UInt16

    public init(x: UInt16, y: UInt16) {
        self.x = x
        self.y = y
    }
}

public enum SceneLineClass: UInt8, CaseIterable, Sendable {
    case minor = 0
    case major = 1
    case route = 2
}

public struct SceneSegment: Equatable, Sendable {
    public let start: ScenePoint
    public let end: ScenePoint
    public let lineClass: SceneLineClass

    public init(start: ScenePoint, end: ScenePoint, lineClass: SceneLineClass) {
        self.start = start
        self.end = end
        self.lineClass = lineClass
    }
}

public enum ManeuverKind: UInt8, CaseIterable, Sendable {
    case straight = 0
    case left = 1
    case right = 2
    case uTurn = 3
    case arrive = 4
}

public struct NavigationScene: Equatable, Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case tooManySegments
        case outOfViewport
        case invalidHeading
    }

    public static let maximumSegments = RenderProtocol.maximumPrimitives

    public let currentPosition: ScenePoint
    public let headingDegrees: UInt16
    public let maneuver: ManeuverKind
    public let distanceMeters: UInt32
    public let segments: [SceneSegment]

    public var roadSegmentCount: Int {
        segments.reduce(into: 0) { count, segment in
            if segment.lineClass != .route { count += 1 }
        }
    }

    public var routeSegmentCount: Int {
        segments.reduce(into: 0) { count, segment in
            if segment.lineClass == .route { count += 1 }
        }
    }

    public init(
        currentPosition: ScenePoint,
        headingDegrees: UInt16,
        maneuver: ManeuverKind,
        distanceMeters: UInt32,
        segments: [SceneSegment]
    ) throws {
        guard segments.count <= Self.maximumSegments else { throw Error.tooManySegments }
        guard headingDegrees <= 359 else { throw Error.invalidHeading }
        guard Self.isInsideViewport(currentPosition),
              segments.allSatisfy({ Self.isInsideViewport($0.start) && Self.isInsideViewport($0.end) }) else {
            throw Error.outOfViewport
        }
        self.currentPosition = currentPosition
        self.headingDegrees = headingDegrees
        self.maneuver = maneuver
        self.distanceMeters = distanceMeters
        self.segments = segments
    }

    public static func synthetic(segmentCount: Int) throws -> NavigationScene {
        guard (0...maximumSegments).contains(segmentCount) else { throw Error.tooManySegments }
        let segments = (0..<segmentCount).map { index in
            let x = UInt16(8 + ((index * 19) % 190))
            let y = UInt16(12 + ((index * 23) % 330))
            let nextX = UInt16(min(RenderProtocol.viewportWidth - 1, Int(x) + 12))
            let nextY = UInt16(min(RenderProtocol.viewportHeight - 1, Int(y) + 9))
            let lineClass: SceneLineClass
            if index % 5 == 0 {
                lineClass = .route
            } else if index % 2 == 0 {
                lineClass = .major
            } else {
                lineClass = .minor
            }
            return SceneSegment(
                start: ScenePoint(x: x, y: y),
                end: ScenePoint(x: nextX, y: nextY),
                lineClass: lineClass
            )
        }
        return try NavigationScene(
            currentPosition: ScenePoint(x: 106, y: 180),
            headingDegrees: 90,
            maneuver: .straight,
            distanceMeters: 120,
            segments: segments
        )
    }

    static func isInsideViewport(_ point: ScenePoint) -> Bool {
        point.x < RenderProtocol.viewportWidth && point.y < RenderProtocol.viewportHeight
    }
}
