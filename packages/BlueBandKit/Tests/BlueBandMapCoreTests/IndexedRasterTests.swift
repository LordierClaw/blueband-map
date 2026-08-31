import XCTest
@testable import BlueBandMapCore

final class IndexedRasterTests: XCTestCase {
    func testBresenhamDrawsHorizontalVerticalAndDiagonalLines() throws {
        var raster = try IndexedRaster()
        raster.drawLine(from: ScreenPoint(x: 2, y: 4), to: ScreenPoint(x: 6, y: 4), color: .minor)
        raster.drawLine(from: ScreenPoint(x: 9, y: 2), to: ScreenPoint(x: 9, y: 6), color: .major)
        raster.drawLine(from: ScreenPoint(x: 12, y: 12), to: ScreenPoint(x: 15, y: 15), color: .route)

        XCTAssertEqual((2...6).map { raster.pixel(x: $0, y: 4) }, Array(repeating: IndexedRaster.Palette.minor.rawValue, count: 5))
        XCTAssertEqual((2...6).map { raster.pixel(x: 9, y: $0) }, Array(repeating: IndexedRaster.Palette.major.rawValue, count: 5))
        XCTAssertEqual((12...15).map { raster.pixel(x: $0, y: $0) }, Array(repeating: IndexedRaster.Palette.route.rawValue, count: 4))
    }

}
