import Foundation
import XCTest
import BlueBandCore
import BlueBandMapCore
@testable import BlueBandMap

@MainActor
final class H1RenderCoordinatorTests: XCTestCase {
    private let run1 = "h1-run-000000000001"
    private let scene1 = "scene-000000000001"

    func testModesAreExplicitAndChooseTheirRenderer() {
        XCTAssertEqual(H1TestMode.allCases.count, 4)
        XCTAssertEqual(H1TestMode.rasterStaticCompact.renderer, .raster)
        XCTAssertEqual(H1TestMode.rasterTileMap.renderer, .raster)
        XCTAssertEqual(H1TestMode.vectorTileMap40.renderer, .vector)
        XCTAssertEqual(H1TestMode.vectorTileMap60.renderer, .vector)
        XCTAssertEqual(H1TestMode.vectorTileMap40.expectedPrimitives, 40)
        XCTAssertEqual(H1TestMode.vectorTileMap60.expectedPrimitives, 60)
        XCTAssertFalse(H1TestMode.rasterStaticCompact.requiresServiceKey)
        XCTAssertTrue(H1TestMode.rasterStaticCompact.requiresTileMapKey)
    }

    func testProviderHTTPStatusIsPreservedWithoutProviderBodyOrKey() async {
        let sender = H1TestSender()
        let coordinator = H1RenderCoordinator(
            session: sender,
            assetProvider: { _, _, _ in throw VietmapStyleError.httpStatus(403) },
            resultTimeout: .seconds(10),
            runIDGenerator: { "h1-run-000000000001" },
            sceneIDGenerator: { "scene-000000000001" }
        )

        await coordinator.start(mode: .vectorTileMap40, tileMapKey: "not-exported")

        XCTAssertEqual(coordinator.state, .failed(mode: .vectorTileMap40, code: "STYLE_HTTP_403"))
        let startedCount = await sender.startedCount
        XCTAssertEqual(startedCount, 0)
    }

    func testTileHTTPStatusIsSeparatedFromStyleWithoutProviderBodyOrKey() async {
        let sender = H1TestSender()
        let coordinator = H1RenderCoordinator(
            session: sender,
            assetProvider: { _, _, _ in throw H1AssetFactory.Error.tileHTTPStatus(404) },
            resultTimeout: .seconds(10),
            runIDGenerator: { "h1-run-000000000001" },
            sceneIDGenerator: { "scene-000000000001" }
        )

        await coordinator.start(mode: .vectorTileMap40, tileMapKey: "not-exported")

        XCTAssertEqual(coordinator.state, .failed(mode: .vectorTileMap40, code: "TILE_HTTP_404"))
        let startedCount = await sender.startedCount
        XCTAssertEqual(startedCount, 0)
    }

    func testStyleAndTileMIMEFailuresRemainDistinguishable() async {
        for (error, code) in [
            (VietmapStyleError.wrongContentType as Swift.Error, "STYLE_MIME"),
            (H1AssetFactory.Error.tileWrongContentType as Swift.Error, "TILE_MIME"),
        ] {
            let sender = H1TestSender()
            let coordinator = H1RenderCoordinator(
                session: sender,
                assetProvider: { _, _, _ in throw error },
                resultTimeout: .seconds(10),
                runIDGenerator: { "h1-run-000000000001" },
                sceneIDGenerator: { "scene-000000000001" }
            )

            await coordinator.start(mode: .vectorTileMap40, tileMapKey: "not-exported")

            XCTAssertEqual(coordinator.state, .failed(mode: .vectorTileMap40, code: code))
        }
    }

    func testReadyBeforePrepareACKIsBufferedAndTransferRemainsStopAndWait() async throws {
        let sender = H1TestSender()
        let provider = H1TestProvider(asset: try makeAsset(kind: .vector))
        let coordinator = makeCoordinator(sender: sender, provider: provider)
        let start = Task { await coordinator.start(mode: .vectorTileMap40) }

        await waitUntil { await sender.startedCount == 1 }
        coordinator.consume(readyEnvelope(runID: run1, sceneID: scene1, renderer: "vector"))
        await sender.acknowledgeNext()
        await waitUntil { await sender.startedCount == 2 }
        let maximumInFlight = await sender.maximumInFlight
        XCTAssertEqual(maximumInFlight, 1)

        await sender.failNext(CancellationError())
        await start.value
        XCTAssertEqual(coordinator.state, .failed(mode: .vectorTileMap40, code: "TRANSFER_CANCELLED"))
        XCTAssertNotNil(coordinator.lastRunRecord)
    }

    func testRejectStopsBeforeAssetBegin() async throws {
        let sender = H1TestSender()
        let provider = H1TestProvider(asset: try makeAsset(kind: .raster))
        let coordinator = makeCoordinator(sender: sender, provider: provider)
        let start = Task { await coordinator.start(mode: .rasterStaticCompact) }

        await waitUntil { await sender.startedCount == 1 }
        coordinator.consume(rejectEnvelope(runID: run1, sceneID: scene1, code: "payloadTooLarge"))
        await sender.acknowledgeNext()
        await start.value

        let steps = await sender.steps
        XCTAssertEqual(steps.map(\.topic), ["render.prepare"])
        XCTAssertEqual(coordinator.state, .failed(mode: .rasterStaticCompact, code: "payloadTooLarge"))
    }

    func testResultBeforeFinalACKIsBufferedAndDisplaysAfterExactConfirmation() async throws {
        let asset = try makeAsset(kind: .vector)
        let sender = H1TestSender()
        let provider = H1TestProvider(asset: asset)
        let coordinator = makeCoordinator(sender: sender, provider: provider)
        let start = Task { await coordinator.start(mode: .vectorTileMap40) }

        await waitUntil { await sender.startedCount == 1 }
        coordinator.consume(readyEnvelope(runID: run1, sceneID: scene1, renderer: "vector"))
        await sender.acknowledgeNext()
        let plan = try RenderTransferPlan.make(asset: asset, runID: run1, sceneID: scene1)
        for index in 0..<plan.count {
            await waitUntil { await sender.startedCount == index + 2 }
            if index == plan.count - 1 {
                coordinator.consume(resultEnvelope(
                    runID: run1, sceneID: scene1, renderer: "vector", success: true,
                    bytes: asset.byteCount, primitives: asset.primitives
                ))
            }
            await sender.acknowledgeNext()
        }
        await start.value

        XCTAssertEqual(coordinator.state, .displayed(
            mode: .vectorTileMap40, runID: run1, hashPrefix: String(asset.sha256.prefix(8))
        ))
        XCTAssertEqual(coordinator.lastRunRecord?.metrics.terminalCode, "displayed")
    }

    func testCurrentResultUsingLegacyBooleanSchemaFailsSchemaInvalid() async throws {
        let asset = try makeAsset(kind: .vector)
        let sender = H1TestSender()
        let provider = H1TestProvider(asset: asset)
        let coordinator = makeCoordinator(sender: sender, provider: provider)
        let start = Task { await coordinator.start(mode: .vectorTileMap40) }

        await waitUntil { await sender.startedCount == 1 }
        coordinator.consume(readyEnvelope(runID: run1, sceneID: scene1, renderer: "vector"))
        await sender.acknowledgeNext()
        let plan = try RenderTransferPlan.make(asset: asset, runID: run1, sceneID: scene1)
        for index in 0..<plan.count {
            await waitUntil { await sender.startedCount == index + 2 }
            if index == plan.count - 1 {
                coordinator.consume(legacyBooleanResultEnvelope(
                    runID: run1, sceneID: scene1, renderer: "vector",
                    bytes: asset.byteCount, primitives: asset.primitives
                ))
            }
            await sender.acknowledgeNext()
        }
        await start.value

        XCTAssertEqual(coordinator.state, .failed(
            mode: .vectorTileMap40, code: "RESULT_SCHEMA_INVALID"
        ))
        XCTAssertEqual(coordinator.lastRunRecord?.metrics.terminalCode, "RESULT_SCHEMA_INVALID")
    }

    func testSuccessfulResultWhileTransferIsInProgressFailsEarly() async throws {
        let asset = try makeAsset(kind: .vector)
        let sender = H1TestSender()
        let provider = H1TestProvider(asset: asset)
        let coordinator = makeCoordinator(sender: sender, provider: provider)
        let start = Task { await coordinator.start(mode: .vectorTileMap40) }

        await waitUntil { await sender.startedCount == 1 }
        coordinator.consume(readyEnvelope(runID: run1, sceneID: scene1, renderer: "vector"))
        await sender.acknowledgeNext()
        await waitUntil { await sender.startedCount == 2 }
        coordinator.consume(resultEnvelope(
            runID: run1, sceneID: scene1, renderer: "vector", success: true,
            bytes: asset.byteCount, primitives: asset.primitives
        ))
        await sender.failNext(CancellationError())
        await start.value

        XCTAssertEqual(coordinator.state, .failed(
            mode: .vectorTileMap40, code: "RESULT_EARLY"
        ))
        XCTAssertEqual(coordinator.lastRunRecord?.metrics.terminalCode, "RESULT_EARLY")
    }

    func testCurrentResultWithMismatchedMetadataFailsMetadataInvalid() async throws {
        let asset = try makeAsset(kind: .vector)
        let sender = H1TestSender()
        let provider = H1TestProvider(asset: asset)
        let coordinator = makeCoordinator(sender: sender, provider: provider)
        let start = Task { await coordinator.start(mode: .vectorTileMap40) }

        await waitUntil { await sender.startedCount == 1 }
        coordinator.consume(readyEnvelope(runID: run1, sceneID: scene1, renderer: "vector"))
        await sender.acknowledgeNext()
        let plan = try RenderTransferPlan.make(asset: asset, runID: run1, sceneID: scene1)
        for index in 0..<plan.count {
            await waitUntil { await sender.startedCount == index + 2 }
            if index == plan.count - 1 {
                coordinator.consume(resultEnvelope(
                    runID: run1, sceneID: scene1, renderer: "vector", success: true,
                    bytes: asset.byteCount + 1, primitives: asset.primitives
                ))
            }
            await sender.acknowledgeNext()
        }
        await start.value

        XCTAssertEqual(coordinator.state, .failed(
            mode: .vectorTileMap40, code: "RESULT_BYTES_MISMATCH"
        ))
        XCTAssertEqual(coordinator.lastRunRecord?.metrics.terminalCode, "RESULT_BYTES_MISMATCH")
    }

    func testStaleResultIsIgnoredAndVectorFailureNeverInvokesRaster() async throws {
        let sender = H1TestSender()
        let provider = H1TestProvider(asset: try makeAsset(kind: .vector))
        let coordinator = makeCoordinator(sender: sender, provider: provider, runIDs: [run1])
        let start = Task { await coordinator.start(mode: .vectorTileMap40) }
        await waitUntil { await sender.startedCount == 1 }
        coordinator.consume(resultEnvelope(
            runID: "h1-run-stale-00001", sceneID: scene1, renderer: "vector", success: true,
            bytes: 3, primitives: 8
        ))
        XCTAssertEqual(coordinator.state, .preparing(mode: .vectorTileMap40, runID: run1))
        coordinator.consume(rejectEnvelope(runID: run1, sceneID: scene1, code: "unsupportedRenderer"))
        await sender.acknowledgeNext()
        await start.value

        let modes = await provider.modes
        XCTAssertEqual(modes, [.vectorTileMap40])
        XCTAssertEqual(coordinator.state, .failed(mode: .vectorTileMap40, code: "unsupportedRenderer"))
    }

    func testDisconnectCancelsOwnershipAndClosesRunRecord() async throws {
        let sender = H1TestSender()
        let provider = H1TestProvider(asset: try makeAsset(kind: .raster))
        let coordinator = makeCoordinator(sender: sender, provider: provider)
        let start = Task { await coordinator.start(mode: .rasterStaticCompact) }
        await waitUntil { await sender.startedCount == 1 }
        coordinator.disconnected()
        await sender.failNext(InterconnectDeliveryError.disconnected)
        await start.value

        XCTAssertEqual(coordinator.state, .failed(mode: .rasterStaticCompact, code: "TRANSFER_DISCONNECTED"))
        XCTAssertTrue(coordinator.requiresReconnect)
        XCTAssertEqual(coordinator.lastRunRecord?.metrics.terminalCode, "TRANSFER_DISCONNECTED")
    }

    private func makeCoordinator(
        sender: H1TestSender,
        provider: H1TestProvider,
        runIDs: [String] = ["h1-run-000000000001"]
    ) -> H1RenderCoordinator {
        let runSource = H1RunIDSource(runIDs)
        return H1RenderCoordinator(
            session: sender,
            assetProvider: { mode, _, _ in await provider.asset(for: mode) },
            resultTimeout: .seconds(10),
            runIDGenerator: { runSource.next() },
            sceneIDGenerator: { "scene-000000000001" }
        )
    }

    private func readyEnvelope(runID: String, sceneID: String, renderer: String) -> ApplicationEnvelope {
        .message(id: "band-ready", source: .band, topic: "render.ready", body: [
            "runId": .string(runID), "sceneId": .string(sceneID), "renderer": .string(renderer),
            "formatVersion": .number(1), "width": .number(212), "height": .number(360),
            "bytes": .number(3), "primitives": .number(renderer == "vector" ? 8 : 0),
        ])
    }

    private func rejectEnvelope(runID: String, sceneID: String, code: String) -> ApplicationEnvelope {
        .message(id: "band-reject", source: .band, topic: "render.reject", body: [
            "runId": .string(runID), "sceneId": .string(sceneID), "code": .string(code),
        ])
    }

    private func resultEnvelope(
        runID: String,
        sceneID: String,
        renderer: String,
        success: Bool,
        bytes: Int,
        primitives: Int
    ) -> ApplicationEnvelope {
        .message(id: "band-result", source: .band, topic: "render.result", body: [
            "runId": .string(runID), "sceneId": .string(sceneID), "renderer": .string(renderer),
            "formatVersion": .number(1), "status": .string(success ? "ok" : "error"), "bytes": .number(Double(bytes)),
            "primitives": .number(Double(primitives)), "renderMs": .number(2),
        ])
    }

    private func legacyBooleanResultEnvelope(
        runID: String,
        sceneID: String,
        renderer: String,
        bytes: Int,
        primitives: Int
    ) -> ApplicationEnvelope {
        .message(id: "legacy-band-result", source: .band, topic: "render.result", body: [
            "runId": .string(runID), "sceneId": .string(sceneID), "renderer": .string(renderer),
            "formatVersion": .number(1), "success": .bool(false), "bytes": .number(Double(bytes)),
            "primitives": .number(Double(primitives)), "renderMs": .number(2),
        ])
    }

    private func makeAsset(kind: RenderKind) throws -> RenderAsset {
        try RenderAsset(kind: kind, formatVersion: 1, width: 212, height: 360, data: Data([1, 2, 3]), primitives: kind == .vector ? 8 : 0)
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<500 {
            if await condition() { return }
            await Task.yield()
        }
        XCTFail("Condition was not met", file: file, line: line)
    }
}

private actor H1TestProvider {
    let assetValue: RenderAsset
    private(set) var modes: [H1TestMode] = []

    init(asset: RenderAsset) { assetValue = asset }

    func asset(for mode: H1TestMode) -> RenderAsset {
        modes.append(mode)
        return assetValue
    }
}

private actor H1TestSender: H1SessionSending {
    private(set) var steps: [RenderTransferStep] = []
    private(set) var inFlight = 0
    private(set) var maximumInFlight = 0
    private var waiters: [CheckedContinuation<String, any Swift.Error>] = []
    var startedCount: Int { steps.count }
    var waitingCount: Int { waiters.count }

    func sendAwaitingAcknowledgement(topic: String, body: [String: JSONValue]) async throws -> String {
        steps.append(RenderTransferStep(topic: topic, body: body))
        inFlight += 1
        maximumInFlight = max(maximumInFlight, inFlight)
        defer { inFlight -= 1 }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, any Swift.Error>) in
            waiters.append(continuation)
        }
    }

    func acknowledgeNext() { waiters.removeFirst().resume(returning: "ack") }
    func failNext(_ error: any Swift.Error) { waiters.removeFirst().resume(throwing: error) }
}

private final class H1RunIDSource: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String]
    private let fallback: String

    init(_ values: [String]) {
        self.values = values
        fallback = values.last ?? "h1-run-000000000001"
    }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        return values.isEmpty ? fallback : values.removeFirst()
    }
}
