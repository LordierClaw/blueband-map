import Foundation
import XCTest
import BlueBandCore
import BlueBandMapCore
@testable import BlueBandMap

@MainActor
final class RouteCardRenderCoordinatorTests: XCTestCase {
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

    func testDefaultWindowIsFourAndPrepareCarriesNavigationPreview() async throws {
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
        XCTAssertEqual(maximumConcurrentChunks, 4)
        XCTAssertEqual(chunksStartedWhileFirstPending, 3)
        XCTAssertEqual(preparedPreview, .object(preview.jsonBody()))
    }
}

private struct NeverReadyRouteCardSession: RouteCardSessionSending {
    func sendAwaitingAcknowledgement(topic: String, body: [String: JSONValue]) async throws -> String { "ack" }
}

private struct ImmediateRouteCardClock: BlueBandClock {
    func sleep(for duration: Duration) async throws {}
}

private actor WindowedRouteCardSession: RouteCardSessionSending {
    typealias Receiver = @MainActor @Sendable (ApplicationEnvelope) -> Void

    private var receiver: Receiver?
    private var prepareBody: [String: JSONValue] = [:]
    private var activeChunks = 0
    private(set) var maximumConcurrentChunks = 0
    private(set) var chunksStartedWhileFirstPending = 0
    private let chunkDelay: Duration
    private let delayFirstChunk: Bool
    private var firstChunkPending = false

    init(chunkDelay: Duration = .milliseconds(5), delayFirstChunk: Bool = false) {
        self.chunkDelay = chunkDelay
        self.delayFirstChunk = delayFirstChunk
    }

    func setReceiver(_ receiver: @escaping Receiver) { self.receiver = receiver }

    func prepareValue(_ key: String) -> JSONValue? { prepareBody[key] }

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
            await receive(RenderProtocol.resultTopic, body: [
                "runId": prepareBody["runId"]!, "sceneId": prepareBody["sceneId"]!,
                "renderer": prepareBody["renderer"]!, "formatVersion": prepareBody["formatVersion"]!,
                "status": .string("ok"), "bytes": prepareBody["bytes"]!,
                "primitives": prepareBody["primitives"]!, "renderMs": .number(1),
                "prepareMs": .number(1), "validateMs": .number(1),
            ])
        }
        return "ack"
    }

    private func receive(_ topic: String, body: [String: JSONValue]) async {
        guard let receiver else { return }
        await receiver(.message(id: "band-\(topic)", source: .band, topic: topic, body: body))
    }
}
