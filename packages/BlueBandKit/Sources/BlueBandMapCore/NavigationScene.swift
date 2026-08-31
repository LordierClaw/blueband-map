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

    public static let maximumSegments = 200

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
        guard (0...RenderProtocol.maximumPrimitives).contains(segmentCount) else { throw Error.tooManySegments }
        let xs: [UInt16] = [16, 52, 88, 124, 160, 196]
        let ys: [UInt16] = [40, 100, 160, 220, 280, 340]
        var grid = [SceneSegment]()
        for y in ys {
            for index in 0..<(xs.count - 1) {
                grid.append(SceneSegment(
                    start: ScenePoint(x: xs[index], y: y),
                    end: ScenePoint(x: xs[index + 1], y: y),
                    lineClass: y == 160 ? .route : .minor
                ))
            }
        }
        for x in xs {
            for index in 0..<(ys.count - 1) {
                grid.append(SceneSegment(
                    start: ScenePoint(x: x, y: ys[index]),
                    end: ScenePoint(x: x, y: ys[index + 1]),
                    lineClass: .major
                ))
            }
        }
        let segments = Array(grid.prefix(segmentCount))
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
