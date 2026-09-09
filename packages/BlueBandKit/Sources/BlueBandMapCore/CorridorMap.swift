import Foundation

public struct CorridorCell: Hashable, Sendable {
    public let column: Int
    public let row: Int
    public var key: String { "\(column):\(row)" }
}

/// Integer translation in the confirmed camera's pixel plane, not GPS coordinates.
public struct CorridorViewport: Equatable, Sendable {
    public enum Error: Swift.Error { case invalidOffset }
    public static let cellSize = 128
    public static let maximumFiles = 30
    public static let maximumResident = 24
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) throws {
        guard (-32768...32768).contains(x), (-32768...32768).contains(y) else { throw Error.invalidOffset }
        self.x = x
        self.y = y
    }

    public var visibleCells: [CorridorCell] {
        let side = Double(Self.cellSize)
        let left = Int(floor(Double(-x) / side)), right = Int(ceil(Double(212 - x) / side))
        let top = Int(floor(Double(-y) / side)), bottom = Int(ceil(Double(520 - y) / side))
        return (top..<bottom).flatMap { row in (left..<right).map { CorridorCell(column: $0, row: row) } }
    }

    /// The route lookahead is expressed in the epoch's original camera plane.
    /// Fetch the current viewport first, then at most one cell's movement ahead.
    public func prioritizedCells(toward point: ScreenPoint) -> [CorridorCell] {
        let dx = Double(point.x) - Double(106 - x), dy = Double(point.y) - Double(374 - y)
        let distance = hypot(dx, dy)
        let visible = visibleCells
        guard distance.isFinite, distance >= 1 else { return visible }
        let step = min(Double(Self.cellSize), distance)
        let nextX = x - Int((dx / distance * step).rounded())
        let nextY = y - Int((dy / distance * step).rounded())
        guard let ahead = try? Self(x: nextX, y: nextY) else { return visible }
        let pinned = Set(visible)
        return Array((visible + ahead.visibleCells.filter { !pinned.contains($0) }).prefix(Self.maximumFiles))
    }
}
