public enum SnapshotPaletteProfile: String, CaseIterable, Codable, Sendable {
    case colors32Labels
    case colors16Labels
    case colors16NoLowPriorityLabels
    case colors16NoLowPriorityLandUse

    public var colorCount: Int { self == .colors32Labels ? 32 : 16 }
    public var keepsLowPriorityLabels: Bool {
        self == .colors32Labels || self == .colors16Labels
    }
    public var keepsLowPriorityLandUse: Bool { self != .colors16NoLowPriorityLandUse }
}

public enum SnapshotPayloadAdmission {
    public static func choose(
        _ candidates: [(profile: SnapshotPaletteProfile, byteCount: Int)]
    ) -> SnapshotPaletteProfile? {
        candidates.first { (1...RenderProtocol.maximumPayloadBytes).contains($0.byteCount) }?.profile
    }
}

public enum ReusableLocationPolicy {
    public static func isReusable(horizontalAccuracyMeters: Double, ageSeconds: Double) -> Bool {
        (0...25).contains(horizontalAccuracyMeters) && (0...10).contains(ageSeconds)
    }
}

public struct ScreenRect: Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public func contains(_ point: ScreenPoint) -> Bool {
        point.x >= x && point.y >= y && point.x < x + width && point.y < y + height
    }
}

public struct SnapshotRefreshContext: Equatable, Sendable {
    public let marker: ScreenPoint?
    public let safeViewport: ScreenRect
    public let maneuverContextChanged: Bool
    public let rerouteSucceeded: Bool
    public let zoomContextLost: Bool

    public init(
        marker: ScreenPoint?,
        safeViewport: ScreenRect,
        maneuverContextChanged: Bool = false,
        rerouteSucceeded: Bool = false,
        zoomContextLost: Bool = false
    ) {
        self.marker = marker
        self.safeViewport = safeViewport
        self.maneuverContextChanged = maneuverContextChanged
        self.rerouteSucceeded = rerouteSucceeded
        self.zoomContextLost = zoomContextLost
    }
}

public enum SnapshotRefreshPolicy {
    public static let defaultSafeViewport = ScreenRect(x: 24, y: 136, width: 164, height: 344)

    public static func shouldRefresh(_ context: SnapshotRefreshContext) -> Bool {
        context.marker.map { !context.safeViewport.contains($0) } ?? true
            || context.maneuverContextChanged
            || context.rerouteSucceeded
            || context.zoomContextLost
    }
}

public struct SnapshotGenerationCoalescer: Sendable {
    private var active: Int?
    private var pending: Int?
    private var latest = -1

    public init() {}

    public mutating func enqueue(_ generation: Int) -> Int? {
        guard generation > latest else { return nil }
        latest = generation
        guard active == nil else { pending = generation; return nil }
        active = generation
        return generation
    }

    public mutating func completed(_ generation: Int) -> Int? {
        guard active == generation else { return nil }
        if let pending {
            active = pending
            self.pending = nil
            return pending
        }
        active = nil
        return nil
    }

    public mutating func reset() {
        active = nil
        pending = nil
        latest = -1
    }
}
