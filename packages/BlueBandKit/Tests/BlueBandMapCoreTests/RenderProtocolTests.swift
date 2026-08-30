import Foundation
import XCTest
import BlueBandCore
@testable import BlueBandMapCore

final class RenderProtocolTests: XCTestCase {
    private let runID = "h1-run-0123456789"
    private let sceneID = "scene-0123456789"

    func testPrepareReadyRejectAndResultBodiesHaveStableFields() throws {
        let asset = try RenderAsset(
            kind: .vector,
            formatVersion: 1,
            width: 212,
            height: 360,
            data: Data(repeating: 0xA5, count: 128),
            primitives: 8
        )
        let prepare = try RenderPrepareBody(runID: runID, sceneID: sceneID, asset: asset)

        XCTAssertEqual(prepare.runID, runID)
        XCTAssertEqual(prepare.sceneID, sceneID)
        XCTAssertEqual(prepare.renderer, .vector)
        XCTAssertEqual(prepare.format, RenderFormat.vector.rawValue)
        XCTAssertEqual(prepare.formatVersion, 1)
        XCTAssertEqual(prepare.width, 212)
        XCTAssertEqual(prepare.height, 360)
        XCTAssertEqual(prepare.bytes, 128)
        XCTAssertEqual(prepare.primitives, 8)
        XCTAssertEqual(prepare.sha256.count, 64)
        XCTAssertTrue(prepare.sha256.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        XCTAssertEqual(Set(prepare.jsonBody().keys), [
            "runId", "sceneId", "renderer", "format", "formatVersion",
            "width", "height", "bytes", "sha256", "primitives",
        ])

        let ready = RenderReadyBody(runID: runID, sceneID: sceneID, prepare: prepare)
        XCTAssertEqual(ready.jsonBody()["runId"], .string(runID))
        XCTAssertEqual(ready.jsonBody()["renderer"], .string("vector"))

        let reject = RenderRejectBody(
            runID: runID,
            sceneID: sceneID,
            code: .payloadTooLarge
        )
        XCTAssertEqual(reject.jsonBody()["code"], .string("payloadTooLarge"))

        let result = RenderResultBody(
            runID: runID,
            sceneID: sceneID,
            renderer: .vector,
            formatVersion: 1,
            success: true,
            bytes: 128,
            primitives: 8,
            validateMilliseconds: 2,
            renderMilliseconds: 4
        )
        XCTAssertEqual(result.jsonBody()["success"], .bool(true))
        XCTAssertEqual(result.jsonBody()["renderMs"], .number(4))
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
            height: 360,
            data: Data([0x01]),
            primitives: 0
        )) { error in
            XCTAssertEqual(error as? RenderAsset.Error, .invalidDimensions)
        }

        XCTAssertThrowsError(try RenderAsset(
            kind: .vector,
            formatVersion: 1,
            width: 212,
            height: 360,
            data: Data([0x01]),
            primitives: 41
        )) { error in
            XCTAssertEqual(error as? RenderAsset.Error, .tooManyPrimitives)
        }

        XCTAssertThrowsError(try RenderAsset(
            kind: .raster,
            formatVersion: 1,
            width: 212,
            height: 360,
            data: Data(repeating: 0, count: RenderProtocol.maximumPayloadBytes + 1),
            primitives: 0
        )) { error in
            XCTAssertEqual(error as? RenderAsset.Error, .tooLarge)
        }
    }

    func testRenderTransferStepsStayWithinEnvelopeAndReconstructData() throws {
        let data = Data(repeating: 0x37, count: 2_048)
        let asset = try RenderAsset(
            kind: .raster,
            formatVersion: 1,
            width: 212,
            height: 360,
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
}
