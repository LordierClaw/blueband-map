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
        let asset = try MapAsset.png(
            data: png,
            expectedWidth: RenderProtocol.viewportWidth,
            expectedHeight: RenderProtocol.viewportHeight
        )
        XCTAssertEqual(asset.width, RenderProtocol.viewportWidth)
        XCTAssertEqual(asset.height, RenderProtocol.viewportHeight)
    }
}
