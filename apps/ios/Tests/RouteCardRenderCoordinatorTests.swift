import Foundation
import XCTest
import BlueBandCore
import BlueBandMapCore
@testable import BlueBandMap

@MainActor
final class RouteCardRenderCoordinatorTests: XCTestCase {
    func testResultAfterFinalACKReturnsToCallerAndAllowsTheNextMap() async throws {
        let session = WindowedRouteCardSession(deferResults: true)
        let coordinator = RouteCardRenderCoordinator(session: session)
        await session.setReceiver { envelope in coordinator.consume(envelope) }
        let asset = try RenderAsset(kind: .raster, formatVersion: 1, width: 212, height: 520,
                                   data: Data(repeating: 0x5A, count: 64), primitives: 0)
        var scenes = Set<String>()
        for _ in 0..<3 {
            let returned = expectation(description: "display result releases the awaiting publisher")
            let operation = Task {
                await coordinator.start(asset: asset)
                returned.fulfill()
            }
            let deadline = ContinuousClock.now + .seconds(2)
            while ContinuousClock.now < deadline {
                if case .waitingForBand = coordinator.state { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            guard case .waitingForBand = coordinator.state else {
                operation.cancel()
                await operation.value
                return XCTFail("must acknowledge map.asset.end before delivering render.result")
            }
            let pendingResult = await session.pendingResult
            let result = try XCTUnwrap(pendingResult)
            await session.deliverResult()
            coordinator.consume(.message(id: "duplicate-result", source: .band,
                topic: RenderProtocol.resultTopic, body: result))
            await fulfillment(of: [returned], timeout: 1)
            XCTAssertEqual(coordinator.lastRunRecord?.metrics.terminalCode, "displayed")
            XCTAssertEqual(coordinator.lastRunRecord?.events.filter { $0.name == "displayed" }.count, 1)
            if let scene = coordinator.lastDisplayedSceneID { scenes.insert(scene) }
            operation.cancel() // bounded cleanup also releases the old implementation's stuck waiter
            await operation.value
        }
        XCTAssertEqual(scenes.count, 3, "successful publication must release ownership for subsequent maps")
    }

    func testTerminalFailureQueriesPeerOnceAndIgnoresUncorrelatedDiagnostics() async throws {
        let requested = expectation(description: "one diagnostic exchange after terminal failure")
        let session = DiagnosticRouteCardSession(requested: requested)
        let coordinator = RouteCardRenderCoordinator(session: session)
        await session.setReceiver { envelope in coordinator.consume(envelope) }
        let asset = try RenderAsset(kind: .raster, formatVersion: 1, width: 212, height: 520,
                                    data: Data(repeating: 0x5A, count: 64), primitives: 0)

        await coordinator.start(asset: asset)
        await fulfillment(of: [requested], timeout: 2)
        XCTAssertTrue(coordinator.diagnostic.contains("peer=rpk27/chunk/off480/got960/err204"))
        let exported = NavigationDebugFormatter.export(
            state: "limitedMap", start: nil, destination: nil, routeDistanceMeters: nil,
            alternativePathCount: nil, instructions: [], entries: [],
            runtime: ["bandTransfer": coordinator.diagnostic]
        )
        XCTAssertTrue(exported.prefix(1024).contains("peer=rpk27/chunk/off480/got960/err204"))
        let diagnostic = coordinator.diagnostic
        coordinator.consume(.message(id: "stale-report", source: .band, topic: "diagnostics.report", body: [
            "request": .string("stale"), "rpk": .number(27), "phase": .string("end"),
            "offset": .number(8192), "received": .number(8192), "sendCode": .number(0)
        ]))
        XCTAssertEqual(coordinator.diagnostic, diagnostic)
        await coordinator.start(asset: asset)
        let count = await session.requestCount
        XCTAssertEqual(count, 1, "a reconnect-required refresh must not probe again")
    }

    func testPeerDiagnosticsValidateNumbersAndIgnoreRepliesAfterDisconnect() async throws {
        let requested = expectation(description: "diagnostic request without automatic reply")
        let session = DiagnosticRouteCardSession(requested: requested, responds: false)
        let coordinator = RouteCardRenderCoordinator(session: session)
        let asset = try RenderAsset(kind: .raster, formatVersion: 1, width: 212, height: 520,
                                    data: Data(repeating: 0x5A, count: 64), primitives: 0)
        await coordinator.start(asset: asset)
        await fulfillment(of: [requested], timeout: 2)
        let lastRequest = await session.lastRequest
        let request = try XCTUnwrap(lastRequest)
        var body: [String: JSONValue] = [
            "request": .string(request), "rpk": .number(27), "phase": .string("chunk"),
            "offset": .number(480), "received": .number(960), "sendCode": .number(204)
        ]
        for invalid in [Double(Int.max), .infinity, .nan, 0.5, -2, 8193] {
            body["offset"] = .number(invalid)
            coordinator.consume(.message(id: "invalid", source: .band, topic: "diagnostics.report", body: body))
            XCTAssertFalse(coordinator.diagnostic.contains("peer=rpk"))
        }
        coordinator.disconnected()
        let diagnostic = coordinator.diagnostic
        body["offset"] = .number(480)
        coordinator.consume(.message(id: "late", source: .band, topic: "diagnostics.report", body: body))
        XCTAssertEqual(coordinator.diagnostic, diagnostic)
    }

    func testBufferedReadyCancelsPrepareTimeoutBeforeSlowTransfer() async throws {
        let session = WindowedRouteCardSession(chunkDelay: .milliseconds(5))
        let coordinator = RouteCardRenderCoordinator(
            session: session,
            resultTimeout: .milliseconds(10),
            transferWindow: 1,
            runIDGenerator: { "nav-run-buffered" },
            sceneIDGenerator: { "scene-buffered" }
        )
        await session.setReceiver { envelope in coordinator.consume(envelope) }
        let asset = try RenderAsset(
            kind: .raster,
            formatVersion: RenderProtocol.formatVersion,
            width: RenderProtocol.viewportWidth,
            height: RenderProtocol.viewportHeight,
            data: Data(repeating: 0x5A, count: 2_048),
            primitives: 0
        )

        await coordinator.start(asset: asset)

        guard case .displayed = coordinator.state else {
            return XCTFail("buffered ready must not time out during transfer: \(coordinator.state)")
        }
    }

    func testPrepareResponseTimeoutTerminatesTheRun() async throws {
        let coordinator = RouteCardRenderCoordinator(
            session: NeverReadyRouteCardSession(),
            clock: ImmediateRouteCardClock(),
            resultTimeout: .seconds(15),
            runIDGenerator: { "nav-run-timeout" },
            sceneIDGenerator: { "scene-timeout" }
        )
        let asset = try RenderAsset(
            kind: .raster,
            formatVersion: RenderProtocol.formatVersion,
            width: RenderProtocol.viewportWidth,
            height: RenderProtocol.viewportHeight,
            data: Data(repeating: 0x5A, count: 64),
            primitives: 0
        )

        await coordinator.start(asset: asset)

        XCTAssertEqual(coordinator.state, .failed(mode: .routeCard, code: "ASSET_READY_TIMEOUT"))
        XCTAssertEqual(coordinator.failureCode, "ASSET_READY_TIMEOUT")
        XCTAssertTrue(coordinator.requiresReconnect)
        XCTAssertTrue(coordinator.diagnostic.contains("terminal=ASSET_READY_TIMEOUT acked=1/4"))
        XCTAssertTrue(coordinator.diagnostic.contains("transferMs=0 window=1"))
    }

    func testChunkAcknowledgementWindowsStayBounded() async throws {
        for window in [1, 2, 4] {
            let session = WindowedRouteCardSession()
            let coordinator = RouteCardRenderCoordinator(
                session: session,
                transferWindow: window,
                runIDGenerator: { "nav-run-window" },
                sceneIDGenerator: { "scene-window" }
            )
            await session.setReceiver { envelope in coordinator.consume(envelope) }
            let asset = try RenderAsset(
                kind: .raster,
                formatVersion: RenderProtocol.formatVersion,
                width: RenderProtocol.viewportWidth,
                height: RenderProtocol.viewportHeight,
                data: Data(repeating: 0x5A, count: 2_048),
                primitives: 0
            )

            await coordinator.start(asset: asset, diagnostics: RouteCardRenderDiagnostics(
                gpsWaitMilliseconds: 12,
                routeRequestMilliseconds: 34,
                styleLoadMilliseconds: 56,
                snapshotMilliseconds: 78,
                paletteReductionMilliseconds: 9,
                paletteSize: 16,
                retainedFillLayers: 3,
                retainedLineLayers: 4,
                retainedSymbolLayers: 5,
                cacheState: "warm"
            ))

            let maximumConcurrentChunks = await session.maximumConcurrentChunks
            XCTAssertEqual(maximumConcurrentChunks, window)
            guard case .displayed = coordinator.state else {
                return XCTFail("window \(window) did not reach displayed")
            }
            XCTAssertEqual(coordinator.lastRunRecord?.metrics.gpsWaitMilliseconds, 12)
            XCTAssertEqual(coordinator.lastRunRecord?.metrics.paletteSize, 16)
            XCTAssertEqual(coordinator.lastRunRecord?.metrics.bandPublicationMilliseconds, 1)
        }
    }

    func testTwoChunkWindowReducesRecordedHardwareACKLatencyWithoutLargerEnvelopes() async throws {
        var durations: [Double] = []
        for window in [1, 2] {
            let session = WindowedRouteCardSession(chunkDelay: .milliseconds(500))
            let coordinator = RouteCardRenderCoordinator(session: session, transferWindow: window)
            await session.setReceiver { envelope in coordinator.consume(envelope) }
            let asset = try RenderAsset(kind: .raster, formatVersion: RenderProtocol.formatVersion,
                width: 212, height: 520, data: Data(repeating: 0x5a, count: 7416), primitives: 0)
            let started = Date()
            await coordinator.start(asset: asset)
            durations.append(Date().timeIntervalSince(started))
            guard case .displayed = coordinator.state else { return XCTFail("window \(window) failed") }
            let concurrent = await session.maximumConcurrentChunks
            XCTAssertEqual(concurrent, window)
        }
        print("TRANSFER 7416B ACK500ms window1=\(durations[0])s window2=\(durations[1])s")
        XCTAssertLessThan(durations[1], durations[0] * 0.65)
    }

    func testDefaultWindowWaitsForEachChunkAcknowledgementAndCarriesNavigationPreview() async throws {
        let session = WindowedRouteCardSession(delayFirstChunk: true)
        let coordinator = RouteCardRenderCoordinator(
            session: session,
            runIDGenerator: { "nav-run-preview" },
            sceneIDGenerator: { "scene-preview" }
        )
        await session.setReceiver { envelope in coordinator.consume(envelope) }
        let asset = try RenderAsset(
            kind: .raster,
            formatVersion: RenderProtocol.formatVersion,
            width: RenderProtocol.viewportWidth,
            height: RenderProtocol.viewportHeight,
            data: Data(repeating: 0x5A, count: 2_048),
            primitives: 0
        )
        let preview = try RenderNavigationPreview(
            maneuver: .right, distanceMeters: 88, street: "Chu Huy Man",
            x: 106, y: 374, headingBucket: 2,
            destinationMode: .visible, destinationX: 106, destinationY: 120
        )

        await coordinator.start(asset: asset, preview: preview)

        let maximumConcurrentChunks = await session.maximumConcurrentChunks
        let chunksStartedWhileFirstPending = await session.chunksStartedWhileFirstPending
        let preparedPreview = await session.prepareValue("preview")
        XCTAssertEqual(maximumConcurrentChunks, 1)
        XCTAssertEqual(chunksStartedWhileFirstPending, 0)
        XCTAssertEqual(preparedPreview, .object(preview.jsonBody()))
    }
}

private struct NeverReadyRouteCardSession: RouteCardSessionSending {
    func sendAwaitingAcknowledgement(topic: String, body: [String: JSONValue]) async throws -> String { "ack" }
}

private struct ImmediateRouteCardClock: BlueBandClock {
    func sleep(for duration: Duration) async throws {}
}

actor WindowedRouteCardSession: RouteCardSessionSending {
    typealias Receiver = @MainActor @Sendable (ApplicationEnvelope) -> Void

    private var receiver: Receiver?
    private var prepareBody: [String: JSONValue] = [:]
    private var activeChunks = 0
    private(set) var maximumConcurrentChunks = 0
    private(set) var chunksStartedWhileFirstPending = 0
    private let chunkDelay: Duration
    private let delayFirstChunk: Bool
    private let failChunks: Bool
    private let deferResults: Bool
    private var firstChunkPending = false
    private(set) var pendingResult: [String: JSONValue]?

    init(chunkDelay: Duration = .milliseconds(5), delayFirstChunk: Bool = false,
         failChunks: Bool = false, deferResults: Bool = false) {
        self.chunkDelay = chunkDelay
        self.delayFirstChunk = delayFirstChunk
        self.failChunks = failChunks
        self.deferResults = deferResults
    }

    func setReceiver(_ receiver: @escaping Receiver) { self.receiver = receiver }

    func prepareValue(_ key: String) -> JSONValue? { prepareBody[key] }

    func deliverResult() async {
        guard let body = pendingResult else { return }
        pendingResult = nil
        await receive(RenderProtocol.resultTopic, body: body)
    }

    func sendAwaitingAcknowledgement(topic: String, body: [String: JSONValue]) async throws -> String {
        if topic == RenderProtocol.prepareTopic {
            prepareBody = body
            await receive(RenderProtocol.readyTopic, body: [
                "runId": body["runId"]!, "sceneId": body["sceneId"]!,
                "renderer": body["renderer"]!, "formatVersion": body["formatVersion"]!,
                "width": body["width"]!, "height": body["height"]!,
                "bytes": body["bytes"]!, "primitives": body["primitives"]!,
            ])
        } else if topic == "map.asset.chunk" {
            if failChunks { throw InterconnectDeliveryError.timeout("fixture-chunk") }
            activeChunks += 1
            maximumConcurrentChunks = max(maximumConcurrentChunks, activeChunks)
            let offset: Int
            if case let .number(value)? = body["offset"] { offset = Int(value) }
            else { offset = -1 }
            if delayFirstChunk, offset == 0 {
                firstChunkPending = true
                try await Task.sleep(for: .milliseconds(25))
                firstChunkPending = false
            } else {
                if delayFirstChunk { try await Task.sleep(for: .milliseconds(1)) }
                if firstChunkPending { chunksStartedWhileFirstPending += 1 }
                try await Task.sleep(for: chunkDelay)
            }
            activeChunks -= 1
        } else if topic == "map.asset.end" {
            let result: [String: JSONValue] = [
                "runId": prepareBody["runId"]!, "sceneId": prepareBody["sceneId"]!,
                "renderer": prepareBody["renderer"]!, "formatVersion": prepareBody["formatVersion"]!,
                "status": .string("ok"), "bytes": prepareBody["bytes"]!,
                "primitives": prepareBody["primitives"]!, "renderMs": .number(1),
                "prepareMs": .number(1), "validateMs": .number(1),
            ]
            if deferResults { pendingResult = result }
            else { await receive(RenderProtocol.resultTopic, body: result) }
        }
        return "ack"
    }

    private func receive(_ topic: String, body: [String: JSONValue]) async {
        guard let receiver else { return }
        await receiver(.message(id: "band-\(topic)", source: .band, topic: topic, body: body))
    }
}

private actor DiagnosticRouteCardSession: RouteCardSessionSending {
    let requested: XCTestExpectation
    let responds: Bool
    private var receiver: WindowedRouteCardSession.Receiver?
    private(set) var requestCount = 0
    private(set) var lastRequest: String?

    init(requested: XCTestExpectation, responds: Bool = true) {
        self.requested = requested
        self.responds = responds
    }
    func setReceiver(_ receiver: @escaping WindowedRouteCardSession.Receiver) { self.receiver = receiver }

    func sendAwaitingAcknowledgement(topic: String, body: [String: JSONValue]) async throws -> String {
        guard topic == "diagnostics.get" else { throw InterconnectDeliveryError.timeout("fixture-prepare") }
        requestCount += 1
        if case let .string(request)? = body["request"] { lastRequest = request }
        if responds {
            await receiver?(.message(id: "peer-report", source: .band, topic: "diagnostics.report", body: [
                "request": body["request"] ?? .null, "rpk": .number(27), "phase": .string("chunk"),
                "offset": .number(480), "received": .number(960), "sendCode": .number(204)
            ]))
        }
        requested.fulfill()
        return "diagnostic-ack"
    }
}
