import Foundation
import XCTest
import BlueBandMapCore
@testable import BlueBandMap

final class IndexedPNGEncoderTests: XCTestCase {
    func testProducesBoundedPNGWithTheExpectedViewport() throws {
        let scene = try NavigationScene.synthetic(segmentCount: 40)
        let raster = try IndexedRaster.render(scene: scene)
        let png = try IndexedPNGEncoder.encode(raster)

        XCTAssertLessThanOrEqual(png.count, RenderProtocol.maximumPayloadBytes)
        XCTAssertEqual(try PNGInspector.dimensions(of: png).width, RenderProtocol.viewportWidth)
        XCTAssertEqual(try PNGInspector.dimensions(of: png).height, RenderProtocol.viewportHeight)
    }
}
