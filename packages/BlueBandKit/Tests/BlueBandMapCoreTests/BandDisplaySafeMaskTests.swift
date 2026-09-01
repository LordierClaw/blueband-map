import XCTest
@testable import BlueBandMapCore

final class BandDisplaySafeMaskTests: XCTestCase {
    func testPhotoEstimatedCapsuleRejectsTopCornerAndKeepsCenter() {
        let mask = BandDisplaySafeMask.smartBand10PhotoEstimate

        XCTAssertTrue(mask.contains(center: ScreenPoint(x: 106, y: 40), resourceWidth: 20, resourceHeight: 20))
        XCTAssertFalse(mask.contains(center: ScreenPoint(x: 30, y: 40), resourceWidth: 20, resourceHeight: 20))
    }

    func testEdgeIndicatorClampsToCurvedContourInAllDirections() {
        let mask = BandDisplaySafeMask.smartBand10PhotoEstimate
        let origin = ScreenPoint(x: 106, y: 374)
        let targets = [
            ScreenPoint(x: 106, y: -500), ScreenPoint(x: 500, y: -500),
            ScreenPoint(x: 500, y: 374), ScreenPoint(x: 500, y: 900),
            ScreenPoint(x: 106, y: 900), ScreenPoint(x: -500, y: 900),
            ScreenPoint(x: -500, y: 374), ScreenPoint(x: -500, y: -500),
        ]

        for target in targets {
            let point = mask.edgePoint(from: origin, toward: target, resourceWidth: 20, resourceHeight: 20)
            XCTAssertTrue(mask.contains(center: point, resourceWidth: 20, resourceHeight: 20), "unsafe edge point for \(target)")
        }
        XCTAssertGreaterThan(mask.edgePoint(from: origin, toward: targets[1], resourceWidth: 20, resourceHeight: 20).x, 106)
        XCTAssertLessThan(mask.edgePoint(from: origin, toward: targets[1], resourceWidth: 20, resourceHeight: 20).y, origin.y)
    }

    func testLargerUserMarkerGetsMoreConservativeClampThanDestinationRing() {
        let mask = BandDisplaySafeMask.smartBand10PhotoEstimate
        let desired = ScreenPoint(x: 0, y: 106)
        let ring = mask.clampedCenter(desired, resourceWidth: 20, resourceHeight: 20)
        let user = mask.clampedCenter(desired, resourceWidth: 46, resourceHeight: 54)

        XCTAssertGreaterThan(user.x, ring.x)
        XCTAssertTrue(mask.contains(center: user, resourceWidth: 46, resourceHeight: 54))
    }

    func testEdgeChevronTipReachesPhysicalContourBeyondTheOldRingCenter() {
        let mask = BandDisplaySafeMask.smartBand10PhotoEstimate
        let physical = mask.withoutVisualMargin
        let origin = ScreenPoint(x: 106, y: 374)
        let targets = [
            ScreenPoint(x: 106, y: -500), ScreenPoint(x: 500, y: -500),
            ScreenPoint(x: 500, y: 374), ScreenPoint(x: 500, y: 900),
            ScreenPoint(x: 106, y: 900), ScreenPoint(x: -500, y: 900),
            ScreenPoint(x: -500, y: 374), ScreenPoint(x: -500, y: -500),
        ]

        for target in targets {
            let conservative = mask.edgePoint(from: origin, toward: target, resourceWidth: 20, resourceHeight: 20)
            let tip = physical.edgePoint(from: origin, toward: target, resourceWidth: 1, resourceHeight: 1)
            XCTAssertTrue(physical.contains(center: tip, resourceWidth: 1, resourceHeight: 1))
            XCTAssertGreaterThan(hypot(Double(tip.x - origin.x), Double(tip.y - origin.y)),
                                 hypot(Double(conservative.x - origin.x), Double(conservative.y - origin.y)))
        }
    }
}
