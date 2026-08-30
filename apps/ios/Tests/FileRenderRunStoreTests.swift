import Foundation
import XCTest
import BlueBandMapCore
@testable import BlueBandMap

final class FileRenderRunStoreTests: XCTestCase {
    func testStoresRunPartsAndExportsOnlySanitizedRecord() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileRenderRunStore(rootURL: root)
        let record = try makeRecord()

        let runDirectory = try store.save(record, previewPNG: Data([0x89, 0x50, 0x4e, 0x47]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runDirectory.appendingPathComponent("run.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runDirectory.appendingPathComponent("events.jsonl").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runDirectory.appendingPathComponent("metrics.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runDirectory.appendingPathComponent("payload.sha256").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runDirectory.appendingPathComponent("preview.png").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: runDirectory.appendingPathComponent("replay-payload.bin").path))

        let exportURL = try store.export(record)
        let exported = try String(contentsOf: exportURL, encoding: .utf8)
        XCTAssertTrue(exported.contains("h1-run-0123456789"))
        XCTAssertFalse(exported.contains("10.759157"))
    }

    private func makeRecord() throws -> RenderRunRecord {
        let identity = try RenderRunIdentity(
            runID: "h1-run-0123456789",
            sceneID: "scene-0123456789",
            renderer: .raster,
            formatVersion: 1,
            width: 212,
            height: 360,
            startedAt: "20260830T101010Z"
        )
        let metrics = try RenderRunMetrics(
            totalMilliseconds: 30,
            providerMilliseconds: 5,
            prepareMilliseconds: 2,
            transferMilliseconds: 18,
            validateMilliseconds: 2,
            renderMilliseconds: 1,
            bytes: 512,
            chunks: 2,
            retries: 0,
            primitives: 0,
            providerCalls: 1,
            ackDurationsMilliseconds: [3],
            terminalCode: "displayed"
        )
        return RenderRunRecord(
            identity: identity,
            events: [],
            metrics: metrics,
            payloadSHA256: String(repeating: "b", count: 64)
        )
    }
}
