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

    public static let transferOptimizedOrder: [Self] = [
        .colors16Labels,
        .colors16NoLowPriorityLabels,
        .colors16NoLowPriorityLandUse,
    ]
}

public enum SnapshotPayloadAdmission {
    public static let preferredMaximumBytes = 5_120

    public static func choose(
        _ candidates: [(profile: SnapshotPaletteProfile, byteCount: Int)]
    ) -> SnapshotPaletteProfile? {
        if let preferred = candidates.first(where: { (1...preferredMaximumBytes).contains($0.byteCount) }) {
            return preferred.profile
        }
        return candidates
            .filter { (1...RenderProtocol.maximumPayloadBytes).contains($0.byteCount) }
            .min { $0.byteCount < $1.byteCount }?
            .profile
    }
}

public enum IndexedPixelPacking {
    public static func fourBit(_ indices: [UInt8], width: Int, height: Int) -> [UInt8] {
        guard width > 0, height > 0, indices.count == width * height,
              indices.allSatisfy({ $0 < 16 }) else { return [] }
        let bytesPerRow = (width + 1) / 2
        var packed = [UInt8](repeating: 0, count: bytesPerRow * height)
        for y in 0..<height {
            for x in 0..<width {
                let value = indices[y * width + x]
                let offset = y * bytesPerRow + x / 2
                packed[offset] |= x.isMultiple(of: 2) ? value << 4 : value
            }
        }
        return packed
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
    public let distanceFromAnchorMeters: Double
    public let secondsSinceLastRefresh: Double
    public let nextManeuverVisible: Bool
    public let rerouteSucceeded: Bool

    public init(
        marker: ScreenPoint?,
        safeViewport: ScreenRect,
        distanceFromAnchorMeters: Double,
        secondsSinceLastRefresh: Double,
        nextManeuverVisible: Bool = true,
        rerouteSucceeded: Bool = false
    ) {
        self.marker = marker
        self.safeViewport = safeViewport
        self.distanceFromAnchorMeters = distanceFromAnchorMeters
        self.secondsSinceLastRefresh = secondsSinceLastRefresh
        self.nextManeuverVisible = nextManeuverVisible
        self.rerouteSucceeded = rerouteSucceeded
    }
}

public enum SnapshotRefreshPolicy {
    public static let defaultSafeViewport = ScreenRect(x: 36, y: 144, width: 140, height: 320)
    public static let minimumRefreshSeconds = 12.0
    public static let movementMeters = 175.0

    public static func shouldRefresh(_ context: SnapshotRefreshContext) -> Bool {
        if context.rerouteSucceeded { return true }
        guard context.secondsSinceLastRefresh >= minimumRefreshSeconds else { return false }
        return context.marker.map { !context.safeViewport.contains($0) } ?? true
            || context.distanceFromAnchorMeters >= movementMeters
            || !context.nextManeuverVisible
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
