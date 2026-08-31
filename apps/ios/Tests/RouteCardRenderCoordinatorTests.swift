import Foundation
import XCTest
import BlueBandCore
import BlueBandMapCore
@testable import BlueBandMap

@MainActor
final class RouteCardRenderCoordinatorTests: XCTestCase {
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

            await coordinator.start(asset: asset)

            XCTAssertEqual(await session.maximumConcurrentChunks, window)
            guard case .displayed = coordinator.state else {
                return XCTFail("window \(window) did not reach displayed")
            }
        }
    }
}

private actor WindowedRouteCardSession: RouteCardSessionSending {
    typealias Receiver = @MainActor @Sendable (ApplicationEnvelope) -> Void

    private var receiver: Receiver?
    private var prepareBody: [String: JSONValue] = [:]
    private var activeChunks = 0
    private(set) var maximumConcurrentChunks = 0

    func setReceiver(_ receiver: @escaping Receiver) { self.receiver = receiver }

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
            try await Task.sleep(for: .milliseconds(5))
            activeChunks -= 1
        } else if topic == "map.asset.end" {
            await receive(RenderProtocol.resultTopic, body: [
                "runId": prepareBody["runId"]!, "sceneId": prepareBody["sceneId"]!,
                "renderer": prepareBody["renderer"]!, "formatVersion": prepareBody["formatVersion"]!,
                "status": .string("ok"), "bytes": prepareBody["bytes"]!,
                "primitives": prepareBody["primitives"]!, "renderMs": .number(1),
            ])
        }
        return "ack"
    }

    private func receive(_ topic: String, body: [String: JSONValue]) async {
        guard let receiver else { return }
        await receiver(.message(id: "band-\(topic)", source: .band, topic: topic, body: body))
    }
}
