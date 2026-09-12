import XCTest
@testable import BlueBandMapCore

final class CorridorMapTests: XCTestCase {
    func testRouteRecoloringTouchesOnlyCellsAlongTheChangedPathWithStrokeMargin() throws {
        let cells = try CorridorViewport(x: 0, y: 0).visibleCells
        let changed = [ScreenPoint(x: 106, y: 374), ScreenPoint(x: 106, y: 370)]
        XCTAssertEqual(cells.filter { $0.intersectsRouteChange(changed) }.map(\.key), ["0:2"])
        let boundary = [ScreenPoint(x: 127, y: 250), ScreenPoint(x: 130, y: 260)]
        XCTAssertEqual(cells.filter { $0.intersectsRouteChange(boundary) }.map(\.key), ["0:1", "1:1", "0:2", "1:2"])
        XCTAssertFalse(cells[0].intersectsRouteChange([]))
    }

    func testViewportMatchesIndependentBandVectorsAndRejectsUnboundedCoordinates() throws {
        XCTAssertEqual(try CorridorViewport(x: 0, y: 0).visibleCells.map(\.key),
            ["0:0", "1:0", "0:1", "1:1", "0:2", "1:2", "0:3", "1:3", "0:4", "1:4"])
        let shifted = try CorridorViewport(x: 1, y: 1).visibleCells
        XCTAssertEqual(shifted.count, 18)
        XCTAssertEqual(shifted.first?.key, "-1:-1")
        XCTAssertEqual(shifted.last?.key, "1:4")
        XCTAssertThrowsError(try CorridorViewport(x: .max, y: 0))
        XCTAssertThrowsError(try CorridorViewport(x: 0, y: -32769))
        for x in [-32768, -129, -128, -1, 0, 1, 127, 128, 32768] {
            for y in [-32768, -129, -1, 0, 127, 128, 32768] {
                let view = try CorridorViewport(x: x, y: y)
                XCTAssertLessThanOrEqual(view.visibleCells.count, 18)
                for point in [ScreenPoint(x: 0, y: 0), ScreenPoint(x: 211, y: 519), ScreenPoint(x: 106, y: 374)] {
                    let covering = view.visibleCells.filter { cell in
                        let left = cell.column * 128 + x, top = cell.row * 128 + y
                        return left <= point.x && point.x < left + 128 && top <= point.y && point.y < top + 128
                    }
                    XCTAssertEqual(covering.count, 1)
                }
            }
        }
    }

    func testPrefetchFollowsRouteAndNeverDelaysVisibleCells() throws {
        let view = try CorridorViewport(x: 0, y: 4)
        let ahead = view.prioritizedCells(toward: ScreenPoint(x: 106, y: 0))
        XCTAssertEqual(Array(ahead.prefix(view.visibleCells.count)), view.visibleCells)
        XCTAssertEqual(Set(ahead).count, ahead.count)
        XCTAssertLessThanOrEqual(ahead.count, 30)
        XCTAssertTrue(ahead.contains { $0.row == -2 })
        XCTAssertFalse(ahead.contains { $0.row > 4 }, "do not prefetch behind the driver")
        let right = view.prioritizedCells(toward: ScreenPoint(x: 1000, y: 370))
        XCTAssertTrue(right.contains { $0.column == 2 })
        XCTAssertFalse(right.contains { $0.column < 0 })
        let moved = try CorridorViewport(x: 0, y: 8)
        XCTAssertTrue(Set(moved.visibleCells).isSubset(of: Set(ahead)), "cached motion needs no new map bytes")
    }
}
