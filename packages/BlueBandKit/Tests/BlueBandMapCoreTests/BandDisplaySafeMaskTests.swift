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
        let user = mask.clampedCenter(desired, resourceWidth: 30, resourceHeight: 38)

        XCTAssertGreaterThan(user.x, ring.x)
        XCTAssertTrue(mask.contains(center: user, resourceWidth: 30, resourceHeight: 38))
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

    func testDestinationEdgePointKeepsTheFull24PixelChevronInsideTheVisualMask() {
        let mask = BandDisplaySafeMask.smartBand10PhotoEstimate
        let edgeMask = mask.withVisualMargin(2)
        let marker = ScreenPoint(x: 106, y: 374)
        let target = ScreenPoint(x: 500, y: -500)
        let oldTip = mask.withoutVisualMargin.edgePoint(
            from: marker, toward: target, resourceWidth: 1, resourceHeight: 1
        )

        let point = edgeMask.destinationEdgePoint(from: marker, toward: target)

        XCTAssertTrue(edgeMask.contains(center: point, resourceWidth: 24, resourceHeight: 24))
        XCTAssertFalse(mask.contains(center: point, resourceWidth: 24, resourceHeight: 24))
        XCTAssertTrue(mask.withoutVisualMargin.contains(center: point, resourceWidth: 24, resourceHeight: 24))
        XCTAssertLessThan(
            hypot(Double(point.x - marker.x), Double(point.y - marker.y)),
            hypot(Double(oldTip.x - marker.x), Double(oldTip.y - marker.y))
        )
    }

    func testDestinationEdgeMaskReachesStraightEdgeAndKeepsCurvedCornersContained() {
        let mask = BandDisplaySafeMask.smartBand10PhotoEstimate.destinationEdge
        let origin = ScreenPoint(x: 106, y: 374)
        let left = mask.destinationEdgePoint(from: origin, toward: ScreenPoint(x: -500, y: 374))
        let right = mask.destinationEdgePoint(from: origin, toward: ScreenPoint(x: 500, y: 374))
        let corner = mask.destinationEdgePoint(from: origin, toward: ScreenPoint(x: -500, y: -500))

        XCTAssertEqual(left.x, 12)
        XCTAssertEqual(right.x, 200)
        XCTAssertTrue(mask.contains(center: corner, resourceWidth: 24, resourceHeight: 24))
        XCTAssertFalse(mask.contains(
            center: ScreenPoint(x: corner.x - 1, y: corner.y - 1),
            resourceWidth: 24, resourceHeight: 24
        ))
    }
}
