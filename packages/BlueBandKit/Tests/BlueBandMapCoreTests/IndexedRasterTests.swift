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

    func testPacksFourPalettePixelsIntoOneBytePerRow() throws {
        var raster = try IndexedRaster()
        try raster.setPixel(x: 0, y: 0, color: .background)
        try raster.setPixel(x: 1, y: 0, color: .minor)
        try raster.setPixel(x: 2, y: 0, color: .major)
        try raster.setPixel(x: 3, y: 0, color: .route)

        let packed = raster.twoBitPixels

        XCTAssertEqual(packed.count, (raster.width + 3) / 4 * raster.height)
        XCTAssertEqual(packed[0], 0b00011011)
        XCTAssertEqual(packed[(raster.width + 3) / 4], 0)
    }

}
