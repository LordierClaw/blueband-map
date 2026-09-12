import Foundation
import XCTest
import BlueBandCore
@testable import BlueBandMapCore

@MainActor
final class CorridorLinkTests: XCTestCase {
    func testUnknownTopicACKDoesNotEnableStreaming() async {
        let link = CorridorLink(timeout: .milliseconds(5)) { _, _ in "ack-only" }
        let enabled = await link.open(scene: "scene-1")
        XCTAssertFalse(enabled)
        XCTAssertFalse(link.ready)
    }

    func testCellChunksAreBoundedAndStoredReplyIsCorrelatedToCommand() async throws {
        let peer = CorridorPeer()
        let link = CorridorLink(timeout: .milliseconds(30)) { try await peer.send($0, $1) }
        peer.receive = link.consume
        let enabled = await link.open(scene: "scene-1")
        XCTAssertTrue(enabled)
        let cell = try XCTUnwrap(CorridorViewport(x: 0, y: 0).visibleCells.first)
        let data = Data(repeating: 0xA5, count: 1024)
        let stored = await link.sendCell(cell, data: data)
        XCTAssertTrue(stored)
        let chunks = peer.messages.filter { $0.topic == "map.cell.chunk" }
        XCTAssertEqual(chunks.count, 5)
        var restored = Data()
        for chunk in chunks.sorted(by: { number($0.body, "offset") < number($1.body, "offset") }) {
            guard case let .string(encoded)? = chunk.body["data"] else { return XCTFail("missing bytes") }
            restored.append(try XCTUnwrap(Data(base64Encoded: encoded)))
            XCTAssertLessThanOrEqual(try ApplicationEnvelope.message(id: "m-0123456789", source: .ios,
                topic: chunk.topic, body: chunk.body).encoded().count, 512)
        }
        XCTAssertEqual(restored, data)
        XCTAssertTrue(link.cachedCells.contains(cell.key))
        let count = peer.messages.count
        let reused = await link.sendCell(cell, data: data)
        XCTAssertTrue(reused)
        XCTAssertEqual(peer.messages.count, count, "already stored cells do not retransmit")
        let replacement = await link.sendCell(cell, data: Data(repeating: 42, count: 1024))
        XCTAssertTrue(replacement)
        XCTAssertGreaterThan(peer.messages.count, count, "changed route pixels replace only that cell")
        peer.correlate = false
        let other = try CorridorViewport(x: 0, y: 0).visibleCells[1]
        let wrongReply = await link.sendCell(other, data: data)
        XCTAssertFalse(wrongReply, "a stale stored response must not finish a new transfer")
        XCTAssertFalse(link.ready, "timeout must force a new epoch before retry")
    }

    func testOnlyConfirmedViewMovesDisplayedCameraAndOldEpochCannotAffectNewScene() async throws {
        let peer = CorridorPeer()
        let link = CorridorLink(timeout: .milliseconds(30)) { try await peer.send($0, $1) }
        peer.receive = link.consume
        _ = await link.open(scene: "scene-1")
        let oldEpoch = try XCTUnwrap(link.epoch)
        let view = try CorridorViewport(x: 0, y: 8)
        let timestamp = Date(timeIntervalSince1970: 1234)
        let accepted = await link.sendView(view, fixTimestamp: timestamp)
        XCTAssertTrue(accepted)
        XCTAssertNil(link.displayedViewport, "ACK is not visual completion")
        peer.reply(topic: "map.stream.state", body: ["epoch": .string(oldEpoch), "seq": .number(1),
            "displayedSeq": .number(1), "code": .string("ok"), "missing": .array([])])
        XCTAssertEqual(link.displayedViewport, view)
        XCTAssertEqual(link.displayedFixTimestamp, timestamp, "latency must use the displayed fix, not the newest pending GPS")
        _ = await link.open(scene: "scene-2")
        XCTAssertNotEqual(link.epoch, oldEpoch)
        peer.reply(topic: "map.stream.state", body: ["epoch": .string(oldEpoch), "seq": .number(1),
            "displayedSeq": .number(1), "code": .string("ok"), "missing": .array([])])
        XCTAssertNil(link.displayedViewport)
    }

    func testStartingNewEpochCannotOverlapACellTransfer() async throws {
        let peer = CorridorPeer()
        let link = CorridorLink(timeout: .milliseconds(30)) { try await peer.send($0, $1) }
        peer.receive = link.consume
        _ = await link.open(scene: "scene-1")
        peer.holdChunks = true
        let cell = try CorridorViewport(x: 0, y: 0).visibleCells[0]
        let transfer = Task { await link.sendCell(cell, data: Data(repeating: 42, count: 1024)) }
        while peer.held.isEmpty { await Task.yield() }
        link.reset()
        peer.holdChunks = false
        peer.held.forEach { $0.resume() }; peer.held = []
        let stored = await transfer.value
        XCTAssertFalse(stored)
        XCTAssertFalse(peer.messages.contains { $0.topic == "map.cell.end" }, "cancelled epoch never sends an end")
        XCTAssertTrue(link.cachedCells.isEmpty)
    }

    func testVisibleReplacementWaitsForMatchingNativeDecode() async throws {
        let peer = CorridorPeer()
        let link = CorridorLink(timeout: .milliseconds(20)) { try await peer.send($0, $1) }
        peer.receive = link.consume
        _ = await link.open(scene: "scene-1")
        let view = try CorridorViewport(x: 0, y: 0), cell = view.visibleCells[0]
        _ = await link.sendCell(cell, data: Data(repeating: 42, count: 100))
        _ = await link.sendView(view)
        peer.reply(topic: "map.stream.state", body: ["epoch": .string(link.epoch!), "displayedSeq": .number(1),
            "code": .string("ok"), "missing": .array([])])
        let unconfirmed = await link.sendCell(cell, data: Data(repeating: 43, count: 100))
        XCTAssertFalse(unconfirmed, "stored bytes alone cannot release a visible replacement decode slot")
    }

    private func number(_ body: [String: JSONValue], _ key: String) -> Double {
        guard case let .number(value)? = body[key] else { return -1 }; return value
    }
}

@MainActor
private final class CorridorPeer {
    var messages: [(topic: String, body: [String: JSONValue])] = []
    var receive: ((ApplicationEnvelope) -> Void)?
    var correlate = true
    var holdChunks = false
    var held: [CheckedContinuation<Void, Never>] = []
    func send(_ topic: String, _ body: [String: JSONValue]) async throws -> String {
        messages.append((topic, body))
        let id = "cmd-\(messages.count)"
        if topic == "map.stream.open" {
            reply(topic: "map.stream.ready", body: ["epoch": body["epoch"]!, "scene": body["scene"]!,
                "version": .number(1), "cellSize": .number(128), "maximumFiles": .number(30), "maximumResident": .number(24)])
        } else if topic == "map.cell.end" {
            reply(topic: "map.cell.result", body: ["epoch": body["epoch"]!, "cell": body["cell"]!,
                "status": .string("stored"), "code": .string("ok"), "evicted": .array([]),
                "request": .string(correlate ? id : "old-end")])
        } else if topic == "map.cell.chunk", holdChunks {
            await withCheckedContinuation { held.append($0) }
        }
        return id
    }
    func reply(topic: String, body: [String: JSONValue]) {
        receive?(.message(id: "band-result", source: .band, topic: topic, body: body))
    }
}
