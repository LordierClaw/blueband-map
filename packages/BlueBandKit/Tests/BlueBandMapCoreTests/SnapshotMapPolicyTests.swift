import XCTest
@testable import BlueBandMapCore

final class SnapshotMapPolicyTests: XCTestCase {
    func testPayloadAdmissionPrefersFiveKiBThenFallsBackToTheSmallestValidCandidate() {
        XCTAssertEqual(SnapshotPaletteProfile.transferOptimizedOrder, [
            .colors16Labels,
            .colors16NoLowPriorityLabels,
            .colors16NoLowPriorityLandUse,
        ])
        XCTAssertEqual(SnapshotPayloadAdmission.preferredMaximumBytes, 5_120)
        XCTAssertEqual(SnapshotPayloadAdmission.choose([
            (.colors16Labels, 5_000),
            (.colors16NoLowPriorityLabels, 3_900),
        ]), .colors16Labels)
        XCTAssertEqual(SnapshotPayloadAdmission.choose([
            (.colors16Labels, 6_000),
            (.colors16NoLowPriorityLabels, 5_000),
            (.colors16NoLowPriorityLandUse, 5_500),
        ]), .colors16NoLowPriorityLabels)
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

    func testUrbanRefreshRequiresTwelveSecondsUnlessRerouteSucceeded() {
        let safe = ScreenRect(x: 36, y: 144, width: 140, height: 320)
        XCTAssertEqual(SnapshotRefreshPolicy.defaultSafeViewport, safe)
        XCTAssertEqual(SnapshotRefreshPolicy.minimumRefreshSeconds, 12)
        XCTAssertEqual(SnapshotRefreshPolicy.movementMeters, 175)
        XCTAssertFalse(SnapshotRefreshPolicy.shouldRefresh(SnapshotRefreshContext(
            marker: ScreenPoint(x: 106, y: 374), safeViewport: safe,
            distanceFromAnchorMeters: 174, secondsSinceLastRefresh: 30
        )))
        XCTAssertFalse(SnapshotRefreshPolicy.shouldRefresh(SnapshotRefreshContext(
            marker: ScreenPoint(x: 10, y: 374), safeViewport: safe,
            distanceFromAnchorMeters: 175, secondsSinceLastRefresh: 11
        )))
        XCTAssertTrue(SnapshotRefreshPolicy.shouldRefresh(SnapshotRefreshContext(
            marker: ScreenPoint(x: 10, y: 374), safeViewport: safe,
            distanceFromAnchorMeters: 10, secondsSinceLastRefresh: 12
        )))
        XCTAssertTrue(SnapshotRefreshPolicy.shouldRefresh(SnapshotRefreshContext(
            marker: ScreenPoint(x: 106, y: 374), safeViewport: safe,
            distanceFromAnchorMeters: 175, secondsSinceLastRefresh: 12
        )))
        XCTAssertTrue(SnapshotRefreshPolicy.shouldRefresh(SnapshotRefreshContext(
            marker: ScreenPoint(x: 106, y: 374), safeViewport: safe,
            distanceFromAnchorMeters: 10, secondsSinceLastRefresh: 12,
            nextManeuverVisible: false
        )))
        XCTAssertTrue(SnapshotRefreshPolicy.shouldRefresh(SnapshotRefreshContext(
            marker: ScreenPoint(x: 106, y: 374), safeViewport: safe,
            distanceFromAnchorMeters: 0, secondsSinceLastRefresh: 0,
            rerouteSucceeded: true
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
