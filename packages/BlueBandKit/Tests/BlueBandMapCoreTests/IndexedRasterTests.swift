import XCTest
@testable import BlueBandMapCore

final class IndexedRasterTests: XCTestCase {
    func testBresenhamDrawsHorizontalVerticalAndDiagonalLines() throws {
        var raster = try IndexedRaster()
        raster.drawLine(from: ScenePoint(x: 2, y: 4), to: ScenePoint(x: 6, y: 4), color: .minor)
        raster.drawLine(from: ScenePoint(x: 9, y: 2), to: ScenePoint(x: 9, y: 6), color: .major)
        raster.drawLine(from: ScenePoint(x: 12, y: 12), to: ScenePoint(x: 15, y: 15), color: .route)

        XCTAssertEqual((2...6).map { raster.pixel(x: $0, y: 4) }, Array(repeating: IndexedRaster.Palette.minor.rawValue, count: 5))
        XCTAssertEqual((2...6).map { raster.pixel(x: 9, y: $0) }, Array(repeating: IndexedRaster.Palette.major.rawValue, count: 5))
        XCTAssertEqual((12...15).map { raster.pixel(x: $0, y: $0) }, Array(repeating: IndexedRaster.Palette.route.rawValue, count: 4))
    }

    func testRouteOverwritesRoadsAndRenderedPixelsStayWithinFourColorPalette() throws {
        let scene = try NavigationScene(
            currentPosition: ScenePoint(x: 10, y: 10),
            headingDegrees: 0,
            maneuver: .straight,
            distanceMeters: 1,
            segments: [
                SceneSegment(start: ScenePoint(x: 2, y: 2), end: ScenePoint(x: 20, y: 20), lineClass: .major),
                SceneSegment(start: ScenePoint(x: 2, y: 2), end: ScenePoint(x: 20, y: 20), lineClass: .route),
            ]
        )
        let raster = try IndexedRaster.render(scene: scene)

        XCTAssertEqual(raster.pixel(x: 10, y: 10), IndexedRaster.Palette.current.rawValue)
        XCTAssertEqual(raster.pixel(x: 8, y: 8), IndexedRaster.Palette.route.rawValue)
        XCTAssertTrue(raster.pixels.allSatisfy { $0 <= IndexedRaster.Palette.current.rawValue })
    }
}
