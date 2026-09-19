import Foundation
import XCTest
import BlueBandCore
@testable import BlueBandMapCore

final class PerformanceTraceTests: XCTestCase {
    func testLateTransportCompletionCannotEnterAReplacementNavigationSession() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let trace = PerformanceTraceRecorder(directory: directory)
        trace.start(metadata: [:])
        let oldOperation = ProcessInfo.processInfo.systemUptime
        trace.end(reason: "stopped")
        trace.start(metadata: [:])
        let current = trace.activeSessionID
        trace.record("ble.ack", requestID: "old", metrics: ["operationStartedUptime": .number(oldOperation)])
        trace.record("ble.ack", requestID: "current", metrics: ["operationStartedUptime": .number(ProcessInfo.processInfo.systemUptime)])
        trace.end(reason: "stopped")
        let records = try decode(await trace.export()).filter { $0["sessionId"] as? String == current && $0["event"] as? String == "ble.ack" }
        XCTAssertEqual(records.compactMap { $0["requestId"] as? String }, ["current"])
    }
    @MainActor
    func testDuplicateTimestampPreservesOriginalIngressCorrelation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let trace = PerformanceTraceRecorder(directory: directory)
        let fixes = PerformanceFixTracker(trace: trace)
        trace.start(metadata: [:])
        let time = Date()
        fixes.received(timestamp: time, accuracy: 5, speed: 3, accepted: true, wall: time, uptime: 100)
        let original = fixes.identifier(time)
        fixes.received(timestamp: time, accuracy: 5, speed: 3, accepted: true, wall: time.addingTimeInterval(0.2), uptime: 100.2)
        XCTAssertEqual(fixes.identifier(time), original)
        trace.end(reason: "stopped")
        let records = try decode(await trace.export())
        XCTAssertEqual(records.filter { $0["event"] as? String == "gps.duplicate" }.count, 1)
    }
    @MainActor
    func testConfirmationIncludesInputAgeAndRejectsWallClockJump() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let trace = PerformanceTraceRecorder(directory: directory)
        let fixes = PerformanceFixTracker(trace: trace)
        trace.start(metadata: [:])
        let timestamp = Date(timeIntervalSince1970: 100)
        fixes.received(timestamp: timestamp, accuracy: 5, speed: 10, accepted: true,
            wall: timestamp.addingTimeInterval(0.2), uptime: 20)
        fixes.confirmed(timestamp: timestamp, mode: "corridor", appState: "background",
            wall: timestamp.addingTimeInterval(0.6), uptime: 20.4)
        fixes.confirmed(timestamp: timestamp, mode: "corridor", appState: "background",
            wall: timestamp.addingTimeInterval(20), uptime: 20.5)
        trace.end(reason: "stopped")
        let records = try decode(await trace.export()).filter { $0["event"] as? String == "map.confirmed" }
        let good = try XCTUnwrap(records.first?["metrics"] as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(good["fixToConfirmMs"] as? Double), 600, accuracy: 0.01)
        XCTAssertEqual(good["clockValid"] as? Bool, true)
        XCTAssertEqual((records.last?["metrics"] as? [String: Any])?["clockValid"] as? Bool, false)
    }
    func testExportKeepsWholeSessionAndTypedMetricsAcrossRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let trace = PerformanceTraceRecorder(directory: directory)
        trace.start(metadata: ["build": .string("test")])
        for index in 0..<150 {
            trace.record("gps.fix", fixID: index, metrics: ["accepted": .bool(true), "gpsInputAgeMs": .number(12)])
        }
        trace.end(reason: "stopped")
        let data = try await trace.export()
        let records = try decode(data)
        XCTAssertEqual(records.filter { $0["event"] as? String == "gps.fix" }.count, 150)
        XCTAssertEqual((records.last?["metrics"] as? [String: Any])?["droppedEvents"] as? Int, 0)
        let reopened = PerformanceTraceRecorder(directory: directory)
        let reopenedData = try await reopened.export()
        XCTAssertEqual(reopenedData, data, "Export must survive relaunch and retain a completed journal")
    }

    func testSizeLimitIsExplicitAndDoesNotPretendSessionIsComplete() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let trace = PerformanceTraceRecorder(directory: directory, maximumBytes: 900)
        trace.start(metadata: [:])
        for index in 0..<30 { trace.record("gps.fix", fixID: index, metrics: ["accepted": .bool(true)]) }
        trace.end(reason: "stopped")
        let records = try decode(await trace.export())
        let status = try XCTUnwrap(records.last?["metrics"] as? [String: Any])
        XCTAssertEqual(status["truncated"] as? Bool, true)
        XCTAssertGreaterThan(status["droppedEvents"] as? Int ?? 0, 0)
    }

    func testOnlyThreeSessionsAreRetainedAndFailureIsObservable() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let trace = PerformanceTraceRecorder(directory: directory)
        for _ in 0..<4 { trace.start(metadata: [:]); trace.end(reason: "stopped") }
        let records = try decode(await trace.export())
        XCTAssertEqual(Set(records.compactMap { $0["sessionId"] as? String }).count, 3)
        let bad = directory.appendingPathComponent("not-a-directory")
        try Data([1]).write(to: bad)
        let broken = PerformanceTraceRecorder(directory: bad)
        broken.start(metadata: [:]); broken.end(reason: "stopped")
        do { _ = try await broken.export(); XCTFail("A failed writer must not export an apparently successful trace") }
        catch { }
    }

    func testConcurrentTransportRecordsStayInsideSessionLifecycle() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let trace = PerformanceTraceRecorder(directory: directory)
        DispatchQueue.concurrentPerform(iterations: 2) { worker in
            if worker == 0 {
                for index in 0..<40 {
                    trace.start(metadata: ["build": .string("race-\(index)")])
                    Thread.sleep(forTimeInterval: 0.0005)
                    trace.end(reason: "stopped")
                }
            } else {
                for _ in 0..<2000 {
                    trace.record("transport.observed")
                    Thread.sleep(forTimeInterval: 0.00005)
                }
            }
        }
        let records = try decode(await trace.export())
        let sessions = Dictionary(grouping: records) { $0["sessionId"] as? String ?? "" }
        XCTAssertEqual(sessions.count, 3)
        XCTAssertTrue(records.contains { $0["event"] as? String == "transport.observed" })
        for events in sessions.values {
            XCTAssertEqual(events.first?["event"] as? String, "session.start")
            XCTAssertEqual(events.first?["eventSeq"] as? Int, 0)
            XCTAssertEqual(events.filter { $0["event"] as? String == "session.end" }.count, 1)
            XCTAssertEqual(events.dropLast().last?["event"] as? String, "session.end")
            XCTAssertEqual(events.last?["event"] as? String, "trace.status")
            XCTAssertEqual((events.last?["metrics"] as? [String: Any])?["droppedEvents"] as? Int, 0)
        }
    }

    func testSuspendedWriterBoundsQueueAndExportsEveryDroppedEvent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = DispatchQueue(label: "trace-test.blocked-writer")
        let trace = PerformanceTraceRecorder(directory: directory, maximumBytes: 32 * 1024 * 1024, writer: writer)
        writer.suspend()
        trace.start(metadata: ["build": .string("overflow")])
        for index in 0..<600 { trace.record("transport.observed", requestID: String(index)) }
        trace.end(reason: "stopped")
        writer.resume()
        let records = try decode(await trace.export())
        let status = try XCTUnwrap(records.last?["metrics"] as? [String: Any])
        XCTAssertEqual(records.count, 257, "256 queued journal rows plus the loss status")
        XCTAssertEqual(status["droppedEvents"] as? Int, 346, "All 602 attempts must be accounted for")
        XCTAssertEqual(status["truncated"] as? Bool, false, "The queue limit, not the byte limit, caused loss")
        XCTAssertEqual(status["writeFailed"] as? Bool, false)
        XCTAssertEqual(records.last?["eventSeq"] as? Int, 602)
        XCTAssertFalse(records.contains { $0["event"] as? String == "session.end" },
            "A dropped end marker must not be fabricated into a completed session")
        let reopened = PerformanceTraceRecorder(directory: directory)
        let reopenedRecords = try decode(await reopened.export())
        XCTAssertEqual((reopenedRecords.last?["metrics"] as? [String: Any])?["droppedEvents"] as? Int, 346)
    }

    private func decode(_ data: Data) throws -> [[String: Any]] {
        try data.split(separator: 10).map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any]) }
    }
}
