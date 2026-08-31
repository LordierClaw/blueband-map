import XCTest
@testable import BlueBandMapCore

final class SnapshotMapPolicyTests: XCTestCase {
    func testPayloadAdmissionUsesTheFirstProfileWithinEightKiB() {
        XCTAssertEqual(SnapshotPaletteProfile.allCases, [
            .colors32Labels,
            .colors16Labels,
            .colors16NoLowPriorityLabels,
            .colors16NoLowPriorityLandUse,
        ])
        XCTAssertEqual(SnapshotPayloadAdmission.choose([
            (.colors32Labels, 8_193),
            (.colors16Labels, 7_900),
            (.colors16NoLowPriorityLabels, 6_000),
        ]), .colors16Labels)
        XCTAssertNil(SnapshotPayloadAdmission.choose([
            (.colors16NoLowPriorityLandUse, 8_193),
        ]))
        XCTAssertEqual(SnapshotPaletteProfile.colors32Labels.colorCount, 32)
        XCTAssertTrue(SnapshotPaletteProfile.colors16Labels.keepsLowPriorityLabels)
        XCTAssertFalse(SnapshotPaletteProfile.colors16NoLowPriorityLabels.keepsLowPriorityLabels)
        XCTAssertFalse(SnapshotPaletteProfile.colors16NoLowPriorityLandUse.keepsLowPriorityLandUse)
    }

    func testRecentAccurateLocationBoundaries() {
        XCTAssertTrue(ReusableLocationPolicy.isReusable(horizontalAccuracyMeters: 25, ageSeconds: 10))
        XCTAssertTrue(ReusableLocationPolicy.isReusable(horizontalAccuracyMeters: 0, ageSeconds: 0))
        XCTAssertFalse(ReusableLocationPolicy.isReusable(horizontalAccuracyMeters: -1, ageSeconds: 0))
        XCTAssertFalse(ReusableLocationPolicy.isReusable(horizontalAccuracyMeters: 25.1, ageSeconds: 10))
        XCTAssertFalse(ReusableLocationPolicy.isReusable(horizontalAccuracyMeters: 25, ageSeconds: 10.1))
        XCTAssertFalse(ReusableLocationPolicy.isReusable(horizontalAccuracyMeters: 5, ageSeconds: -0.1))
    }

    func testRefreshOnlyForSpecifiedContextChanges() {
        let safe = ScreenRect(x: 24, y: 136, width: 164, height: 344)
        XCTAssertFalse(SnapshotRefreshPolicy.shouldRefresh(SnapshotRefreshContext(
            marker: ScreenPoint(x: 106, y: 374), safeViewport: safe
        )))
        XCTAssertTrue(SnapshotRefreshPolicy.shouldRefresh(SnapshotRefreshContext(
            marker: ScreenPoint(x: 10, y: 374), safeViewport: safe
        )))
        XCTAssertTrue(SnapshotRefreshPolicy.shouldRefresh(SnapshotRefreshContext(
            marker: ScreenPoint(x: 106, y: 374), safeViewport: safe, maneuverContextChanged: true
        )))
        XCTAssertTrue(SnapshotRefreshPolicy.shouldRefresh(SnapshotRefreshContext(
            marker: ScreenPoint(x: 106, y: 374), safeViewport: safe, rerouteSucceeded: true
        )))
        XCTAssertTrue(SnapshotRefreshPolicy.shouldRefresh(SnapshotRefreshContext(
            marker: ScreenPoint(x: 106, y: 374), safeViewport: safe, zoomContextLost: true
        )))
    }

    func testGenerationCoalescerReplacesPendingAndRejectsStaleCompletion() {
        var coalescer = SnapshotGenerationCoalescer()
        XCTAssertEqual(coalescer.enqueue(1), 1)
        XCTAssertNil(coalescer.enqueue(2))
        XCTAssertNil(coalescer.enqueue(3))
        XCTAssertNil(coalescer.completed(2))
        XCTAssertEqual(coalescer.completed(1), 3)
        XCTAssertNil(coalescer.completed(1))
        XCTAssertNil(coalescer.completed(3))
    }
}
