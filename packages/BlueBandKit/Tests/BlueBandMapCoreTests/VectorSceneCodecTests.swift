import Foundation
import XCTest
@testable import BlueBandMapCore

final class VectorSceneCodecTests: XCTestCase {
    func testHeaderAndFirstRecordUseTheFrozenLittleEndianBytes() throws {
        let scene = try NavigationScene(
            currentPosition: ScenePoint(x: 10, y: 20),
            headingDegrees: 270,
            maneuver: .right,
            distanceMeters: 900,
            segments: [
                SceneSegment(start: ScenePoint(x: 0, y: 1), end: ScenePoint(x: 212 - 1, y: 359), lineClass: .minor),
                SceneSegment(start: ScenePoint(x: 2, y: 3), end: ScenePoint(x: 4, y: 5), lineClass: .major),
                SceneSegment(start: ScenePoint(x: 6, y: 7), end: ScenePoint(x: 8, y: 9), lineClass: .route),
            ]
        )

        let encoded = try VectorSceneCodec.encode(scene)
        XCTAssertEqual(Array(encoded.prefix(22)), [
            0x42, 0x42, 0x4d, 0x56, 0x01,
            0xd4, 0x00, 0x68, 0x01,
            0x02, 0x01,
            0x0a, 0x00, 0x14, 0x00,
            0x0e, 0x01, 0x02,
            0x84, 0x03, 0x00, 0x00,
        ])
        XCTAssertEqual(Array(encoded[22..<31]), [0x00, 0x00, 0x01, 0x00, 0xd3, 0x00, 0x67, 0x01, 0x00])
        XCTAssertEqual(encoded.count, 22 + (3 * 9))
    }

    func testCodecRoundTripsSyntheticFixturesAndRejectsMalformedCounts() throws {
        for count in [40, 60] {
            let scene = try NavigationScene.synthetic(segmentCount: count)
            let decoded = try VectorSceneCodec.decode(try VectorSceneCodec.encode(scene))
            XCTAssertEqual(decoded, scene)
        }

        var malformed = Data(repeating: 0, count: 22)
        malformed.replaceSubrange(0..<4, with: [0x42, 0x42, 0x4d, 0x56])
        malformed[4] = 1
        malformed[5] = 0xd4
        malformed[7] = 0x68
        malformed[8] = 0x01
        malformed[9] = 61
        XCTAssertThrowsError(try VectorSceneCodec.decode(malformed)) { error in
            XCTAssertEqual(error as? VectorSceneCodec.Error, .tooManySegments)
        }
    }

    func testCodecRejectsWrongMagicVersionLengthAndViewport() throws {
        let scene = try NavigationScene.synthetic(segmentCount: 8)
        let valid = try VectorSceneCodec.encode(scene)

        var wrongMagic = valid
        wrongMagic[0] = 0
        XCTAssertThrowsError(try VectorSceneCodec.decode(wrongMagic)) { error in
            XCTAssertEqual(error as? VectorSceneCodec.Error, .invalidMagic)
        }

        var wrongVersion = valid
        wrongVersion[4] = 2
        XCTAssertThrowsError(try VectorSceneCodec.decode(wrongVersion)) { error in
            XCTAssertEqual(error as? VectorSceneCodec.Error, .unsupportedVersion)
        }

        XCTAssertThrowsError(try VectorSceneCodec.decode(valid.dropLast())) { error in
            XCTAssertEqual(error as? VectorSceneCodec.Error, .invalidLength)
        }

        var wrongWidth = valid
        wrongWidth[5] = 0xd3
        XCTAssertThrowsError(try VectorSceneCodec.decode(wrongWidth)) { error in
            XCTAssertEqual(error as? VectorSceneCodec.Error, .invalidViewport)
        }
    }
}
