import Foundation
import XCTest
@testable import BlueBandMapCore

final class RenderRunTests: XCTestCase {
    func testMetricsCalculateDeterministicAckPercentilesAndKeepCounters() throws {
        let metrics = try RenderRunMetrics(
            totalMilliseconds: 120,
            providerMilliseconds: 25,
            prepareMilliseconds: 8,
            transferMilliseconds: 70,
            validateMilliseconds: 4,
            renderMilliseconds: 3,
            bytes: 4_096,
            chunks: 16,
            retries: 1,
            primitives: 20,
            providerCalls: 1,
            ackDurationsMilliseconds: [4, 10, 20, 40],
            terminalCode: "displayed"
        )

        XCTAssertEqual(metrics.ackP50Milliseconds, 10)
        XCTAssertEqual(metrics.ackP95Milliseconds, 40)
        XCTAssertEqual(metrics.ackMaxMilliseconds, 40)
        XCTAssertEqual(metrics.chunks, 16)
        XCTAssertEqual(metrics.providerCalls, 1)
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
        XCTAssertTrue(text.contains("h1-run-0123456789"))
        XCTAssertTrue(text.contains("ackP95Ms"))
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
            providerCalls: 0,
            ackDurationsMilliseconds: [],
            terminalCode: "failed"
        )) { error in
            XCTAssertEqual(error as? RenderRunMetrics.Error, .negativeValue)
        }
    }

    private func makeRecord() throws -> RenderRunRecord {
        let identity = try RenderRunIdentity(
            runID: "h1-run-0123456789",
            sceneID: "scene-0123456789",
            renderer: .vector,
            formatVersion: 1,
            width: 212,
            height: 360,
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
            bytes: 4_096,
            chunks: 16,
            retries: 1,
            primitives: 20,
            providerCalls: 1,
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
