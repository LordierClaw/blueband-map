import Foundation

public struct IndexedRaster: Equatable, Sendable {
    public enum Palette: UInt8, Sendable {
        case background = 0
        case minor = 1
        case major = 2
        case route = 3

        public static var current: Palette { .route }
    }

    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidDimensions
        case outOfBounds
    }

    public let width: Int
    public let height: Int
    public private(set) var pixels: [UInt8]

    public init(
        width: Int = RenderProtocol.viewportWidth,
        height: Int = RenderProtocol.viewportHeight,
        fill: Palette = .background
    ) throws {
        guard width == RenderProtocol.viewportWidth, height == RenderProtocol.viewportHeight else {
            throw Error.invalidDimensions
        }
        self.width = width
        self.height = height
        self.pixels = Array(repeating: fill.rawValue, count: width * height)
    }

    public func pixel(x: Int, y: Int) -> UInt8 {
        guard x >= 0, x < width, y >= 0, y < height else { return Palette.background.rawValue }
        return pixels[y * width + x]
    }

    public mutating func setPixel(x: Int, y: Int, color: Palette) throws {
        guard x >= 0, x < width, y >= 0, y < height else { throw Error.outOfBounds }
        pixels[y * width + x] = color.rawValue
    }

    public mutating func drawLine(from start: ScenePoint, to end: ScenePoint, color: Palette) {
        var x0 = Int(start.x)
        var y0 = Int(start.y)
        let x1 = Int(end.x)
        let y1 = Int(end.y)
        let dx = abs(x1 - x0)
        let sx = x0 < x1 ? 1 : -1
        let dy = -abs(y1 - y0)
        let sy = y0 < y1 ? 1 : -1
        var error = dx + dy

        while true {
            if x0 >= 0, x0 < width, y0 >= 0, y0 < height {
                pixels[y0 * width + x0] = color.rawValue
            }
            if x0 == x1 && y0 == y1 { break }
            let twiceError = 2 * error
            if twiceError >= dy {
                error += dy
                x0 += sx
            }
            if twiceError <= dx {
                error += dx
                y0 += sy
            }
        }
    }

    public static func render(scene: NavigationScene) throws -> IndexedRaster {
        var raster = try IndexedRaster()
        for lineClass in [SceneLineClass.minor, .major, .route] {
            for segment in scene.segments where segment.lineClass == lineClass {
                raster.drawLine(from: segment.start, to: segment.end, color: palette(for: lineClass))
            }
        }
        try raster.setPixel(
            x: Int(scene.currentPosition.x),
            y: Int(scene.currentPosition.y),
            color: .current
        )
        return raster
    }

    private static func palette(for lineClass: SceneLineClass) -> Palette {
        switch lineClass {
        case .minor: .minor
        case .major: .major
        case .route: .route
        }
    }
}
