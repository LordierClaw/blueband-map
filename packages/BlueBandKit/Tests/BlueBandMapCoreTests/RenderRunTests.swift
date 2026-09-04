import Foundation
import XCTest
@testable import BlueBandMapCore

final class RenderRunTests: XCTestCase {
    func testCPUCacheStatesPreserveCurrentTransferMetrics() throws {
        for state in ["cpu-cold", "cpu-warm"] {
            let metrics = try RenderRunMetrics(totalMilliseconds: 3000, providerMilliseconds: 0,
                prepareMilliseconds: 100, transferMilliseconds: 2900, validateMilliseconds: 0,
                renderMilliseconds: 0, bytes: 4833, chunks: 12, retries: 0, primitives: 0,
                providerCalls: 0, transferWindow: 2, cacheState: state,
                ackDurationsMilliseconds: [500], terminalCode: "displayed")
            XCTAssertEqual(metrics.cacheState, state)
            XCTAssertEqual(metrics.transferWindow, 2)
            XCTAssertEqual(metrics.transferMilliseconds, 2900)
        }
    }

    func testMetricsCalculateDeterministicAckPercentilesAndKeepCounters() throws {
        let metrics = try RenderRunMetrics(
            totalMilliseconds: 120,
            providerMilliseconds: 25,
            prepareMilliseconds: 8,
            transferMilliseconds: 70,
            validateMilliseconds: 4,
            renderMilliseconds: 3,
            bytes: 1_024,
            chunks: 7,
            retries: 1,
            primitives: 0,
            providerCalls: 1,
            gpsWaitMilliseconds: 12,
            routeRequestMilliseconds: 25,
            styleLoadMilliseconds: 14,
            snapshotMilliseconds: 22,
            paletteReductionMilliseconds: 9,
            transferPrepareMilliseconds: 5,
            bandWriteMilliseconds: 6,
            bandDecodeMilliseconds: 7,
            bandPublicationMilliseconds: 8,
            paletteSize: 16,
            retainedFillLayers: 7,
            retainedLineLayers: 28,
            retainedSymbolLayers: 5,
            transferWindow: 1,
            cacheState: "warm",
            ackDurationsMilliseconds: [4, 10, 20, 40],
            terminalCode: "displayed"
        )

        XCTAssertEqual(metrics.ackP50Milliseconds, 10)
        XCTAssertEqual(metrics.ackP95Milliseconds, 40)
        XCTAssertEqual(metrics.ackMaxMilliseconds, 40)
        XCTAssertEqual(metrics.chunks, 7)
        XCTAssertEqual(metrics.providerCalls, 1)
        XCTAssertEqual(metrics.paletteSize, 16)
        XCTAssertEqual(metrics.retainedLineLayers, 28)
        XCTAssertEqual(metrics.transferWindow, 1)
    }

    func testSanitizedExportContainsNoCredentialsIdentifiersOrExactCoordinates() throws {
        let record = try makeRecord()
        let exported = try record.sanitizedExportData()
        let text = String(decoding: exported, as: UTF8.self)
        XCTAssertLessThan(exported.count, 1_024)
        XCTAssertFalse(text.contains("\n"))

        for privateValue in [
            "00112233445566778899aabbccddeeff",
            "vietmap-service-key",
            "vietmap-tilemap-key",
            "AA:BB:CC:DD:EE:FF",
            "10.759157",
            "106.675859",
        ] {
            XCTAssertFalse(text.contains(privateValue), "Export leaked \(privateValue)")
        }
        XCTAssertFalse(text.contains("nav-run-0123456789"))
        XCTAssertFalse(text.contains("scene-0123456789"))
        XCTAssertFalse(text.contains(String(repeating: "a", count: 64)))
        XCTAssertTrue(text.contains("payloadSHA256Prefix"))
        XCTAssertTrue(text.contains("ackP95Ms"))
    }

    func testLongRasterExportStaysValidAndBounded() throws {
        let base = try makeRecord()
        let metrics = try RenderRunMetrics(
            totalMilliseconds: 45_842,
            providerMilliseconds: 313,
            prepareMilliseconds: 94,
            transferMilliseconds: 45_196,
            validateMilliseconds: 0,
            renderMilliseconds: 239,
            bytes: 1_024,
            chunks: 7,
            retries: 0,
            primitives: 0,
            providerCalls: 1,
            paletteSize: 16,
            transferWindow: 1,
            cacheState: "warm",
            ackDurationsMilliseconds: Array(repeating: 420, count: 121),
            terminalCode: "displayed"
        )
        let record = RenderRunRecord(
            identity: base.identity,
            events: base.events,
            metrics: metrics,
            payloadSHA256: base.payloadSHA256
        )

        let data = try record.sanitizedExportData()
        XCTAssertLessThan(data.count, 1_024)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
    }

    func testMetricsRejectNegativeDurationsAndCounters() {
        XCTAssertThrowsError(try RenderRunMetrics(
            totalMilliseconds: -1,
            providerMilliseconds: 0,
            prepareMilliseconds: 0,
            transferMilliseconds: 0,
            validateMilliseconds: 0,
            renderMilliseconds: 0,
            bytes: 0,
            chunks: 0,
            retries: 0,
            primitives: 0,
            providerCalls: 1,
            ackDurationsMilliseconds: [],
            terminalCode: "failed"
        )) { error in
            XCTAssertEqual(error as? RenderRunMetrics.Error, .negativeValue)
        }
    }

    private func makeRecord() throws -> RenderRunRecord {
        let identity = try RenderRunIdentity(
            runID: "nav-run-0123456789",
            sceneID: "scene-0123456789",
            renderer: .raster,
            formatVersion: 1,
            width: 212,
            height: 520,
            startedAt: "20260830T101010Z"
        )
        let event = try RenderRunEvent(sequence: 1, name: "transfer-complete", milliseconds: 70)
        let metrics = try RenderRunMetrics(
            totalMilliseconds: 120,
            providerMilliseconds: 25,
            prepareMilliseconds: 8,
            transferMilliseconds: 70,
            validateMilliseconds: 4,
            renderMilliseconds: 3,
            bytes: 1_024,
            chunks: 7,
            retries: 1,
            primitives: 0,
            providerCalls: 0,
            paletteSize: 16,
            transferWindow: 1,
            cacheState: "cold",
            ackDurationsMilliseconds: [4, 10, 20, 40],
            terminalCode: "displayed"
        )
        return RenderRunRecord(
            identity: identity,
            events: [event],
            metrics: metrics,
            payloadSHA256: String(repeating: "a", count: 64)
        )
    }
}
