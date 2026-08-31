import Foundation
import ImageIO
import XCTest
import BlueBandMapCore
@testable import BlueBandMap

final class IndexedPNGEncoderTests: XCTestCase {
    func testRouteCardPNGStaysWithinTheHardwareBudget() throws {
        let route = RoutePlan(
            points: [
                GeoPoint(latitude: 10, longitude: 106),
                GeoPoint(latitude: 10.001, longitude: 106),
                GeoPoint(latitude: 10.002, longitude: 106.0005),
            ],
            instructions: [
                RouteInstruction(distanceMeters: 180, headingDegrees: 0, sign: 2, interval: 1...2, streetName: "Next Road"),
            ],
            distanceMeters: 250
        )
        let scene = try RouteCardBuilder.build(route: route, progressIndex: 0, sideRoads: [])
        let png = try IndexedPNGEncoder.encode(try IndexedRaster.render(routeCard: scene))

        XCTAssertLessThanOrEqual(png.count, 1_024)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 212)
        XCTAssertEqual(image.height, 360)
    }
}
