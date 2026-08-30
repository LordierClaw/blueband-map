import XCTest
@testable import BlueBandMapCore

final class NavigationSceneTests: XCTestCase {
    func testSyntheticFixturesHaveTheRequestedBoundedSizes() throws {
        XCTAssertEqual(try NavigationScene.synthetic(segmentCount: 8).segments.count, 8)
        XCTAssertEqual(try NavigationScene.synthetic(segmentCount: 20).segments.count, 20)
        XCTAssertEqual(try NavigationScene.synthetic(segmentCount: 40).segments.count, 40)
    }

    func testSceneRejectsMoreThanFortySegmentsAndOutOfViewportPoints() {
        XCTAssertThrowsError(try NavigationScene.synthetic(segmentCount: 41)) { error in
            XCTAssertEqual(error as? NavigationScene.Error, .tooManySegments)
        }

        XCTAssertThrowsError(try NavigationScene(
            currentPosition: ScenePoint(x: 212, y: 0),
            headingDegrees: 0,
            maneuver: .straight,
            distanceMeters: 1,
            segments: []
        )) { error in
            XCTAssertEqual(error as? NavigationScene.Error, .outOfViewport)
        }
    }

    func testSceneCountsRoadAndRouteSegments() throws {
        let scene = try NavigationScene(
            currentPosition: ScenePoint(x: 10, y: 20),
            headingDegrees: 270,
            maneuver: .right,
            distanceMeters: 900,
            segments: [
                SceneSegment(start: ScenePoint(x: 0, y: 0), end: ScenePoint(x: 1, y: 1), lineClass: .minor),
                SceneSegment(start: ScenePoint(x: 2, y: 2), end: ScenePoint(x: 3, y: 3), lineClass: .major),
                SceneSegment(start: ScenePoint(x: 4, y: 4), end: ScenePoint(x: 5, y: 5), lineClass: .route),
            ]
        )

        XCTAssertEqual(scene.roadSegmentCount, 2)
        XCTAssertEqual(scene.routeSegmentCount, 1)
    }
}
