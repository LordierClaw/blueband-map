import Foundation

public struct BandDisplaySafeMask: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let inset: Double
    public let topCenterY: Double
    public let bottomCenterY: Double
    public let topRadius: Double
    public let bottomRadius: Double
    public let visualMargin: Double

    // Hardware-accepted Smart Band 10 production mask. Changes require a dedicated calibration task.
    public static let smartBand10PhotoEstimate = BandDisplaySafeMask(
        width: 212,
        height: 520,
        inset: 12,
        topCenterY: 106,
        bottomCenterY: 413,
        topRadius: 94,
        bottomRadius: 94,
        visualMargin: 6
    )

    public init(
        width: Int,
        height: Int,
        inset: Double,
        topCenterY: Double,
        bottomCenterY: Double,
        topRadius: Double,
        bottomRadius: Double,
        visualMargin: Double
    ) {
        self.width = width
        self.height = height
        self.inset = inset
        self.topCenterY = topCenterY
        self.bottomCenterY = bottomCenterY
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
        self.visualMargin = visualMargin
    }

    public var withoutVisualMargin: Self {
        withVisualMargin(0)
    }

    public var destinationEdge: Self {
        Self(
            width: width,
            height: height,
            inset: 0,
            topCenterY: topCenterY,
            bottomCenterY: bottomCenterY,
            topRadius: topRadius,
            bottomRadius: bottomRadius,
            visualMargin: 0
        )
    }

    public func withVisualMargin(_ margin: Double) -> Self {
        Self(
            width: width,
            height: height,
            inset: inset,
            topCenterY: topCenterY,
            bottomCenterY: bottomCenterY,
            topRadius: topRadius,
            bottomRadius: bottomRadius,
            visualMargin: margin
        )
    }

    public func contains(
        center: ScreenPoint,
        resourceWidth: Int,
        resourceHeight: Int
    ) -> Bool {
        let halfWidth = Double(resourceWidth) / 2 + visualMargin
        let halfHeight = Double(resourceHeight) / 2 + visualMargin
        return [
            (Double(center.x) - halfWidth, Double(center.y) - halfHeight),
            (Double(center.x) + halfWidth, Double(center.y) - halfHeight),
            (Double(center.x) - halfWidth, Double(center.y) + halfHeight),
            (Double(center.x) + halfWidth, Double(center.y) + halfHeight),
        ].allSatisfy(containsPixel)
    }

    public func clampedCenter(
        _ desired: ScreenPoint,
        resourceWidth: Int,
        resourceHeight: Int
    ) -> ScreenPoint {
        edgePoint(
            from: ScreenPoint(x: width / 2, y: height / 2),
            toward: desired,
            resourceWidth: resourceWidth,
            resourceHeight: resourceHeight
        )
    }

    public func destinationEdgePoint(from origin: ScreenPoint, toward target: ScreenPoint) -> ScreenPoint {
        edgePoint(from: origin, toward: target, resourceWidth: 24, resourceHeight: 24)
    }

    public func edgePoint(
        from origin: ScreenPoint,
        toward target: ScreenPoint,
        resourceWidth: Int,
        resourceHeight: Int
    ) -> ScreenPoint {
        if contains(center: target, resourceWidth: resourceWidth, resourceHeight: resourceHeight) { return target }
        let safeOrigin = contains(center: origin, resourceWidth: resourceWidth, resourceHeight: resourceHeight)
            ? origin : ScreenPoint(x: width / 2, y: height / 2)
        var lower = 0.0, upper = 1.0
        for _ in 0..<32 {
            let fraction = (lower + upper) / 2
            let candidate = interpolated(safeOrigin, target, fraction)
            if contains(center: candidate, resourceWidth: resourceWidth, resourceHeight: resourceHeight) {
                lower = fraction
            } else {
                upper = fraction
            }
        }
        var result = interpolated(safeOrigin, target, lower)
        while !contains(center: result, resourceWidth: resourceWidth, resourceHeight: resourceHeight), result != safeOrigin {
            result = ScreenPoint(
                x: result.x + (safeOrigin.x == result.x ? 0 : safeOrigin.x > result.x ? 1 : -1),
                y: result.y + (safeOrigin.y == result.y ? 0 : safeOrigin.y > result.y ? 1 : -1)
            )
        }
        return result
    }

    private func containsPixel(_ point: (Double, Double)) -> Bool {
        let (x, y) = point
        let centerX = Double(width) / 2
        guard x >= inset, x <= Double(width) - inset, y >= inset, y <= Double(height) - inset else { return false }
        if y < topCenterY { return hypot(x - centerX, y - topCenterY) <= topRadius }
        if y > bottomCenterY { return hypot(x - centerX, y - bottomCenterY) <= bottomRadius }
        return true
    }

    private func interpolated(_ start: ScreenPoint, _ end: ScreenPoint, _ fraction: Double) -> ScreenPoint {
        ScreenPoint(
            x: Int((Double(start.x) + Double(end.x - start.x) * fraction).rounded()),
            y: Int((Double(start.y) + Double(end.y - start.y) * fraction).rounded())
        )
    }
}
