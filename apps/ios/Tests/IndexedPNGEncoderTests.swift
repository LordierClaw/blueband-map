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

        XCTAssertLessThanOrEqual(png.count, RenderProtocol.maximumPayloadBytes)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 212)
        XCTAssertEqual(image.height, 520)
    }

    func testReportedRouteGeometryStaysWithinTheHardwareBudget() throws {
        let points = try GooglePolyline5.decode(
            "ofl_CacpfSeB~@eCtAwAw@oBfAUI}@qAsBhAc@TwBdAq@^{@b@KHk@XyB|@y@Tb@nBd@fBzA`GbAvDj@fB\\jAjFvMVjAJx@D|@?dICxVi@NHlA?vACd@Ib@Sl@oEvR}AzGiArEa@bBs@nDUx@y@dD_AhEu@tCMp@A`@CLUd@_@rAQz@QfAi@rBk@jCq@AaAAoDf@q@No@NwAb@wAt@kF|D_Lp~@}@nGe@zDc@fCShAMz@[dBEZYtBE^KzBGz@G`@MPWJODIFQ^e@vA[z@i@~A]bAa@jAa@lAo@jB{@fCs@tBY|@o@BgDLS?PxAv@xDj@fCa@Lh@dChCvKxA`HoEzB}Az@kBbAuAp@uAp@[PgChAa@La@bBMp@CFEBQ`AaAxEw@fD_@dBC^?r@?~@Ef@GTu@vAKR}@hAQHe@h@QNuCnAoD]uDaAaDnF]p@"
        )
        let route = RoutePlan(
            points: points,
            instructions: [
                RouteInstruction(distanceMeters: 153.2, headingDegrees: 330, sign: 0, interval: 0...1, streetName: "Chu Huy Mân")
            ],
            distanceMeters: 9_490.1
        )
        let scene = try RouteCardBuilder.build(route: route, progressIndex: 0, sideRoads: [])

        let png = try IndexedPNGEncoder.encode(try IndexedRaster.render(routeCard: scene))

        XCTAssertLessThanOrEqual(png.count, RenderProtocol.maximumPayloadBytes)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 212)
        XCTAssertEqual(image.height, 520)
    }
}
