import XCTest
import BlueBandCore
@testable import BlueBandMapCore

final class NavigationUpdateTests: XCTestCase {
    func testBodyIsBoundedAndUsesStableFields() throws {
        let update = try NavigationUpdate(
            scene: "scene-0123456789", seq: 7, x: 106, y: 320,
            maneuver: .right, distanceMeters: 180,
            street: String(repeating: "Đ", count: 40), status: .navigating
        )
        XCTAssertLessThanOrEqual(update.street.utf8.count, 48)
        XCTAssertEqual(Set(update.jsonBody().keys), [
            "scene", "seq", "x", "y", "maneuver", "distanceM", "street", "status",
        ])
        let envelope = ApplicationEnvelope.message(
            id: "nav-0123456789", source: .ios, topic: NavigationUpdate.topic, body: update.jsonBody()
        )
        XCTAssertLessThanOrEqual(try envelope.encoded().count, 512)
    }

    func testRejectsInvalidSceneSequenceAndMarker() {
        XCTAssertNoThrow(try NavigationUpdate(
            scene: "scene", seq: 0, x: 211, y: 519, maneuver: .straight,
            distanceMeters: 0, street: "", status: .navigating
        ))
        XCTAssertThrowsError(try NavigationUpdate(
            scene: "", seq: 0, x: 106, y: 320, maneuver: .straight,
            distanceMeters: 0, street: "", status: .navigating
        ))
        XCTAssertThrowsError(try NavigationUpdate(
            scene: "scene", seq: -1, x: 212, y: 320, maneuver: .straight,
            distanceMeters: 0, street: "", status: .navigating
        ))
        XCTAssertThrowsError(try NavigationUpdate(
            scene: "scene", seq: 0, x: 106, y: 520, maneuver: .straight,
            distanceMeters: 0, street: "", status: .navigating
        ))
    }

    func testCoalescerReplacesPendingUpdateWithNewest() throws {
        let first = try update(seq: 1)
        let stale = try update(seq: 2)
        let newest = try update(seq: 3)
        var coalescer = NavigationUpdateCoalescer()

        XCTAssertEqual(coalescer.enqueue(first), first)
        XCTAssertNil(coalescer.enqueue(stale))
        XCTAssertNil(coalescer.enqueue(newest))
        XCTAssertEqual(coalescer.completed(), newest)
        XCTAssertNil(coalescer.completed())
    }

    private func update(seq: Int) throws -> NavigationUpdate {
        try NavigationUpdate(
            scene: "scene", seq: seq, x: 106, y: 320, maneuver: .straight,
            distanceMeters: 100, street: "Road", status: .navigating
        )
    }
}
