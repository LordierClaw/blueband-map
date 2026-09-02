import Foundation
import XCTest
import BlueBandCore
@testable import BlueBandMapCore

final class RenderProtocolTests: XCTestCase {
    private let runID = "nav-run-0123456789"
    private let sceneID = "scene-0123456789"

    func testPrepareReadyRejectAndResultBodiesHaveStableFields() throws {
        let asset = try RenderAsset(
            kind: .raster,
            formatVersion: 1,
            width: 212,
            height: 520,
            data: Data(repeating: 0xA5, count: 128),
            primitives: 0
        )
        let preview = try RenderNavigationPreview(
            maneuver: .right,
            distanceMeters: 88,
            street: String(repeating: "Đ", count: 40),
            x: 106,
            y: 374,
            headingBucket: 3,
            destinationMode: .edge,
            destinationX: 180,
            destinationY: 260
        )
        let prepare = try RenderPrepareBody(runID: runID, sceneID: sceneID, asset: asset, preview: preview)

        XCTAssertEqual(prepare.runID, runID)
        XCTAssertEqual(prepare.sceneID, sceneID)
        XCTAssertEqual(prepare.renderer, .raster)
        XCTAssertEqual(prepare.format, RenderFormat.raster.rawValue)
        XCTAssertEqual(prepare.formatVersion, 1)
        XCTAssertEqual(prepare.width, 212)
        XCTAssertEqual(prepare.height, 520)
        XCTAssertEqual(prepare.bytes, 128)
        XCTAssertEqual(prepare.primitives, 0)
        XCTAssertLessThanOrEqual(try XCTUnwrap(prepare.preview).street.utf8.count, 48)
        XCTAssertEqual(prepare.sha256.count, 64)
        XCTAssertTrue(prepare.sha256.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        XCTAssertEqual(Set(prepare.jsonBody().keys), [
            "runId", "sceneId", "renderer", "format", "formatVersion",
            "width", "height", "bytes", "sha256", "primitives", "preview",
        ])
        XCTAssertEqual(prepare.jsonBody()["preview"], .object(preview.jsonBody()))
        XCTAssertEqual(preview.jsonBody()["x"], .number(106))
        XCTAssertEqual(preview.jsonBody()["heading"], .number(3))
        XCTAssertEqual(preview.jsonBody()["destinationMode"], .string("edge"))
        let envelope = ApplicationEnvelope.message(
            id: "prepare-0123456789", source: .ios,
            topic: RenderProtocol.prepareTopic, body: prepare.jsonBody()
        )
        XCTAssertLessThanOrEqual(try envelope.encoded().count, ApplicationEnvelope.maximumEncodedSize)

        let ready = RenderReadyBody(runID: runID, sceneID: sceneID, prepare: prepare)
        XCTAssertEqual(ready.jsonBody()["runId"], .string(runID))
        XCTAssertEqual(ready.jsonBody()["renderer"], .string("raster"))

        let reject = RenderRejectBody(
            runID: runID,
            sceneID: sceneID,
            code: .payloadTooLarge
        )
        XCTAssertEqual(reject.jsonBody()["code"], .string("payloadTooLarge"))

        let result = RenderResultBody(
            runID: runID,
            sceneID: sceneID,
            renderer: .raster,
            formatVersion: 1,
            success: true,
            bytes: 128,
            primitives: 0,
            validateMilliseconds: 2,
            renderMilliseconds: 4
        )
        XCTAssertEqual(result.jsonBody(), [
            "runId": .string(runID),
            "sceneId": .string(sceneID),
            "renderer": .string("raster"),
            "formatVersion": .number(1),
            "status": .string("ok"),
            "bytes": .number(128),
            "primitives": .number(0),
            "validateMs": .number(2),
            "renderMs": .number(4),
        ])
    }

    func testNavigationPreviewRejectsNegativeDistance() {
        let edge = BandDisplaySafeMask.smartBand10PhotoEstimate.withVisualMargin(2).destinationEdgePoint(
            from: ScreenPoint(x: 106, y: 374), toward: ScreenPoint(x: 500, y: 260)
        )
        XCTAssertThrowsError(try RenderNavigationPreview(
            maneuver: .straight, distanceMeters: -1, street: "Road",
            x: 106, y: 374, headingBucket: 0,
            destinationMode: .hidden, destinationX: 0, destinationY: 0
        ))
        XCTAssertThrowsError(try RenderNavigationPreview(
            maneuver: .straight, distanceMeters: 1, street: "Road",
            x: -1, y: 374, headingBucket: 0,
            destinationMode: .hidden, destinationX: 0, destinationY: 0
        ))
        XCTAssertThrowsError(try RenderNavigationPreview(
            maneuver: .straight, distanceMeters: 1, street: "Road",
            x: 20, y: 20, headingBucket: 0,
            destinationMode: .hidden, destinationX: 0, destinationY: 0
        ))
        XCTAssertThrowsError(try RenderNavigationPreview(
            maneuver: .straight, distanceMeters: 1, street: "Road",
            x: 106, y: 374, headingBucket: 8,
            destinationMode: .hidden, destinationX: 0, destinationY: 0
        ))
        XCTAssertThrowsError(try RenderNavigationPreview(
            maneuver: .straight, distanceMeters: 1, street: "Road",
            x: 106, y: 374, headingBucket: 0,
            destinationMode: .hidden, destinationX: 1, destinationY: 0
        ))
        XCTAssertNoThrow(try RenderNavigationPreview(
            maneuver: .straight, distanceMeters: 1, street: "Road",
            x: 106, y: 374, headingBucket: 0,
            destinationMode: .edge, destinationX: edge.x, destinationY: edge.y
        ))
        XCTAssertThrowsError(try RenderNavigationPreview(
            maneuver: .straight, distanceMeters: 1, street: "Road",
            x: 106, y: 374, headingBucket: 0,
            destinationMode: .visible, destinationX: edge.x, destinationY: edge.y
        ))
    }

    func testRejectCodesAndProtocolTopicsAreStable() {
        XCTAssertEqual(RenderRejectCode.allCases.map(\.rawValue), [
            "unsupportedRenderer",
            "unsupportedFormatVersion",
            "busy",
            "payloadTooLarge",
            "tooManyPrimitives",
            "invalidDimensions",
            "insufficientStorage",
        ])
        XCTAssertEqual(RenderProtocol.prepareTopic, "render.prepare")
        XCTAssertEqual(RenderProtocol.readyTopic, "render.ready")
        XCTAssertEqual(RenderProtocol.rejectTopic, "render.reject")
        XCTAssertEqual(RenderProtocol.resultTopic, "render.result")
    }

    func testRenderAssetRejectsPayloadAndShapeViolations() {
        XCTAssertThrowsError(try RenderAsset(
            kind: .raster,
            formatVersion: 1,
            width: 211,
            height: 520,
            data: Data([0x01]),
            primitives: 0
        )) { error in
            XCTAssertEqual(error as? RenderAsset.Error, .invalidDimensions)
        }

        XCTAssertThrowsError(try RenderAsset(
            kind: .raster,
            formatVersion: 1,
            width: 212,
            height: 520,
            data: Data([0x01]),
            primitives: 1
        )) { error in
            XCTAssertEqual(error as? RenderAsset.Error, .tooManyPrimitives)
        }

        XCTAssertNoThrow(try RenderAsset(
            kind: .raster,
            formatVersion: 1,
            width: 212,
            height: 520,
            data: Data(repeating: 0, count: 8_192),
            primitives: 0
        ))

        XCTAssertThrowsError(try RenderAsset(
            kind: .raster,
            formatVersion: 1,
            width: 212,
            height: 520,
            data: Data(repeating: 0, count: 8_193),
            primitives: 0
        )) { error in
            XCTAssertEqual(error as? RenderAsset.Error, .tooLarge)
        }
    }

    func testRenderTransferStepsStayWithinEnvelopeAndReconstructData() throws {
        let data = Data(repeating: 0x37, count: 8_192)
        let asset = try RenderAsset(
            kind: .raster,
            formatVersion: 1,
            width: 212,
            height: 520,
            data: data,
            primitives: 0
        )
        let steps = try RenderTransferPlan.make(asset: asset, runID: runID, sceneID: sceneID)

        XCTAssertEqual(steps.first?.topic, "map.asset.begin")
        XCTAssertEqual(steps.last?.topic, "map.asset.end")
        XCTAssertTrue(steps.dropFirst().dropLast().allSatisfy { $0.topic == "map.asset.chunk" })

        var reconstructed = Data()
        for step in steps {
            let envelope = ApplicationEnvelope.message(
                id: String(repeating: "\\", count: 32),
                source: .ios,
                topic: step.topic,
                body: step.body
            )
            XCTAssertLessThanOrEqual(try envelope.encoded().count, ApplicationEnvelope.maximumEncodedSize)
            if step.topic == "map.asset.chunk",
               case let .string(encoded)? = step.body["data"] {
                reconstructed.append(try XCTUnwrap(Data(base64Encoded: encoded)))
            }
        }
        XCTAssertEqual(reconstructed, data)
        XCTAssertEqual(steps.first?.body["renderer"], .string("raster"))
        XCTAssertEqual(steps.first?.body["format"], .string(RenderFormat.raster.rawValue))
        XCTAssertEqual(steps.first?.body["primitives"], .number(0))
    }

    func testRenderTransferUsesActualIdentifiersWithoutAnObsoleteChunkCountCap() throws {
        let actualRunID = "nav-run-0123456789abcdef"
        let actualSceneID = "scene-0123456789abcdef"
        let compact = try RenderAsset(
            kind: .raster,
            formatVersion: 1,
            width: 212,
            height: 520,
            data: Data(repeating: 0x37, count: 8_192),
            primitives: 0
        )
        let steps = try RenderTransferPlan.make(asset: compact, runID: actualRunID, sceneID: actualSceneID)
        let firstChunk = try XCTUnwrap(steps.first { $0.topic == "map.asset.chunk" })
        guard case let .string(encoded)? = firstChunk.body["data"] else { return XCTFail("missing chunk data") }
        XCTAssertGreaterThan(try XCTUnwrap(Data(base64Encoded: encoded)?.count), 320)
        XCTAssertLessThan(steps.count - 2, 20)
    }
}
