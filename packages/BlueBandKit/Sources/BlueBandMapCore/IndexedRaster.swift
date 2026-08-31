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

    public var twoBitPixels: [UInt8] {
        let bytesPerRow = (width + 3) / 4
        var packed = [UInt8](repeating: 0, count: bytesPerRow * height)
        for y in 0..<height {
            for x in 0..<width {
                packed[y * bytesPerRow + x / 4] |= pixels[y * width + x] << (6 - (x % 4) * 2)
            }
        }
        return packed
    }

    public mutating func setPixel(x: Int, y: Int, color: Palette) throws {
        guard x >= 0, x < width, y >= 0, y < height else { throw Error.outOfBounds }
        pixels[y * width + x] = color.rawValue
    }

    public mutating func drawLine(
        from start: ScreenPoint,
        to end: ScreenPoint,
        color: Palette,
        thickness: Int = 1
    ) {
        let radius = max(0, thickness / 2)
        var x0 = start.x
        var y0 = start.y
        let x1 = end.x
        let y1 = end.y
        let dx = abs(x1 - x0)
        let sx = x0 < x1 ? 1 : -1
        let dy = -abs(y1 - y0)
        let sy = y0 < y1 ? 1 : -1
        var error = dx + dy

        while true {
            for y in (y0 - radius)...(y0 + radius) {
                for x in (x0 - radius)...(x0 + radius) where x >= 0 && x < width && y >= 0 && y < height {
                    pixels[y * width + x] = color.rawValue
                }
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

    public static func render(routeCard: RouteCardScene) throws -> IndexedRaster {
        var raster = try IndexedRaster()
        for road in routeCard.sideRoads {
            raster.drawPolyline(road.points, color: road.isMajor ? .major : .minor, thickness: road.isMajor ? 2 : 1)
        }
        for line in routeCard.traveledRoute {
            raster.drawPolyline(line.points, color: .minor, thickness: 3)
        }
        for line in routeCard.upcomingRoute {
            raster.drawPolyline(line.points, color: .route, thickness: 5)
        }
        raster.drawDot(at: routeCard.maneuverPoint, color: .route, radius: 4)
        return raster
    }

    private mutating func drawPolyline(_ points: [ScreenPoint], color: Palette, thickness: Int) {
        guard points.count >= 2 else { return }
        for pair in zip(points, points.dropFirst()) {
            drawLine(
                from: pair.0,
                to: pair.1,
                color: color,
                thickness: thickness
            )
        }
    }

    private mutating func drawDot(at point: ScreenPoint, color: Palette, radius: Int) {
        for y in max(0, point.y - radius)...min(height - 1, point.y + radius) {
            for x in max(0, point.x - radius)...min(width - 1, point.x + radius) {
                if (x - point.x) * (x - point.x) + (y - point.y) * (y - point.y) <= radius * radius {
                    pixels[y * width + x] = color.rawValue
                }
            }
        }
    }

}
