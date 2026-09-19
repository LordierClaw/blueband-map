import Foundation
import BlueBandCore
import Crypto

/// Correlates received fixes using the phone's clock; never synchronizes a watch clock.
@MainActor
public final class PerformanceFixTracker {
    private struct Fix {
        let id: Int
        let wall: Date
        let uptime: TimeInterval
        let inputAge: Double
    }
    public let trace: PerformanceTraceRecorder
    private var fixes: [Date: Fix] = [:]
    private var nextID = 0
    private var lastConfirmation: TimeInterval?

    public init(trace: PerformanceTraceRecorder) { self.trace = trace }
    public func reset() { fixes.removeAll(); nextID = 0; lastConfirmation = nil }
    public func identifier(_ timestamp: Date) -> Int? { fixes[timestamp]?.id }

    public func received(timestamp: Date, accuracy: Double, speed: Double, accepted: Bool,
                         reason: String = "callback", wall: Date = Date(),
                         uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if accepted, let existing = fixes[timestamp] {
            trace.record("gps.duplicate", fixID: existing.id, metrics: ["reason": .string(reason)])
            return
        }
        nextID += 1
        let age = wall.timeIntervalSince(timestamp) * 1000
        if accepted {
            fixes[timestamp] = Fix(id: nextID, wall: wall, uptime: uptime, inputAge: age)
            // ponytail: 128 recent fixes cover current bounded pipelines; missing correlation stays unknown.
            if fixes.count > 128, let oldest = fixes.min(by: { $0.value.id < $1.value.id })?.key { fixes.removeValue(forKey: oldest) }
        }
        trace.record("gps.fix", fixID: nextID, metrics: ["accepted": .bool(accepted),
            "gpsInputAgeMs": .number(age), "sampleUptimeMs": .number(uptime * 1000), "accuracyM": .number(accuracy.isFinite ? accuracy : -1),
            "speedMps": .number(speed.isFinite ? speed : -1), "reason": .string(reason)])
    }

    public func confirmed(timestamp: Date, mode: String, appState: String, scene: String? = nil,
                          epoch: String? = nil, viewSequence: Int? = nil,
                          wall: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let fix = fixes[timestamp]
        let elapsed = fix.map { (uptime - $0.uptime) * 1000 }
        let clockValid = fix.map { $0.inputAge >= 0 && uptime >= $0.uptime &&
            abs(wall.timeIntervalSince($0.wall) - (uptime - $0.uptime)) < 0.1 } ?? false
        trace.record("map.confirmed", fixID: fix?.id, scene: scene, epoch: epoch, viewSequence: viewSequence,
            metrics: ["mode": .string(mode), "appState": .string(appState),
                "clockValid": .bool(clockValid), "sampleUptimeMs": .number(uptime * 1000), "initial": .bool(lastConfirmation == nil),
                "appToConfirmMs": elapsed.map(JSONValue.number) ?? .null,
                "fixToConfirmMs": fix.map { .number($0.inputAge + (elapsed ?? 0)) } ?? .null,
                "frameGapMs": lastConfirmation.map { .number((uptime - $0) * 1000) } ?? .null])
        lastConfirmation = uptime
    }

    public static func routeFingerprint(_ points: [GeoPoint]) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: (try? encoder.encode(points)) ?? Data()).map { String(format: "%02x", $0) }.joined()
    }
}

/// A bounded diagnostic journal. It never waits for file I/O on the caller's thread.
public final class PerformanceTraceRecorder: @unchecked Sendable {
    private final class Session: @unchecked Sendable {
        let id = UUID().uuidString.lowercased()
        let started = ProcessInfo.processInfo.systemUptime
        var sequence = 0
        var pending = 0
        var dropped = 0
        var truncated = false
        var failed = false
        var lastMilliseconds = 0.0
        // File properties are accessed only on writer.
        var handle: FileHandle?
        var bytes = 0
        var closed = false
        var timer: DispatchSourceTimer?
    }

    private let directory: URL
    private let maximumBytes: Int
    private let writer: DispatchQueue
    private let lock = NSLock()
    private var current: Session?
    private var sessions: [Session] = []
    private var storageFailed = false

    public convenience init(directory: URL, maximumBytes: Int = 32 * 1024 * 1024) {
        self.init(directory: directory, maximumBytes: maximumBytes,
            writer: DispatchQueue(label: "dev.lordierclaw.bluebandmap.trace", qos: .utility))
    }

    init(directory: URL, maximumBytes: Int, writer: DispatchQueue) {
        self.directory = directory
        self.maximumBytes = max(512, maximumBytes)
        self.writer = writer
    }

    public func start(metadata: [String: JSONValue]) {
        end(reason: "replaced")
        let session = Session()
        var values = metadata
        values["wallUTC"] = .string(ISO8601DateFormatter().string(from: Date()))
        values["nativeMemory"] = .null
        lock.lock()
        current = session
        sessions.append(session)
        sessions = Array(sessions.suffix(3))
        writer.async { [self] in
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = journal(session)
                guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
                #if os(iOS)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
                #endif
                session.handle = try FileHandle(forWritingTo: url)
                let files = try journalFiles()
                for old in files.dropLast(3) {
                    try FileManager.default.removeItem(at: old)
                    try? FileManager.default.removeItem(at: old.appendingPathExtension("status"))
                }
                let timer = DispatchSource.makeTimerSource(queue: writer)
                timer.schedule(deadline: .now() + 1, repeating: 1)
                timer.setEventHandler { [weak self, weak session] in
                    guard let self, let session else { return }
                    self.flush(session)
                }
                session.timer = timer
                timer.resume()
            } catch { markFailed(session) }
        }
        recordLocked("session.start", session: session, metrics: values)
        lock.unlock()
    }

    public var activeSessionID: String? {
        lock.lock(); defer { lock.unlock() }; return current?.id
    }

    public func record(_ event: String, source: String = "ios", expectedSessionID: String? = nil, fixID: Int? = nil,
                       scene: String? = nil, epoch: String? = nil, viewSequence: Int? = nil,
                       requestID: String? = nil, metrics: [String: JSONValue] = [:]) {
        lock.lock()
        defer { lock.unlock() }
        guard let session = current, expectedSessionID == nil || expectedSessionID == session.id else { return }
        if event.hasPrefix("ble."), case let .number(started)? = metrics["operationStartedUptime"],
           !started.isFinite || started < session.started { return }
        recordLocked(event, session: session, source: source, fixID: fixID, scene: scene, epoch: epoch,
            viewSequence: viewSequence, requestID: requestID, metrics: metrics)
    }

    // Caller owns lock: lifecycle markers and concurrent transport events stay ordered.
    private func recordLocked(_ event: String, session: Session, source: String = "ios", fixID: Int? = nil,
                              scene: String? = nil, epoch: String? = nil, viewSequence: Int? = nil,
                              requestID: String? = nil, metrics: [String: JSONValue] = [:]) {
        let elapsed = max(0, (ProcessInfo.processInfo.systemUptime - session.started) * 1000)
        var record: [String: JSONValue] = [
            "schemaVersion": .number(1), "sessionId": .string(session.id),
            "eventSeq": .number(Double(session.sequence)), "monotonicMs": .number(elapsed),
            "source": .string(source), "event": .string(event), "metrics": .object(metrics)
        ]
        if let fixID { record["fixId"] = .number(Double(fixID)) }
        if let scene { record["scene"] = .string(scene) }
        if let epoch { record["epoch"] = .string(epoch) }
        if let viewSequence { record["viewSeq"] = .number(Double(viewSequence)) }
        if let requestID { record["requestId"] = .string(requestID) }
        session.sequence += 1
        session.lastMilliseconds = elapsed
        guard session.pending < 256, !session.truncated, !session.failed,
              let data = try? JSONEncoder().encode(record), data.count <= 65536 else {
            session.dropped += 1
            return
        }
        session.pending += 1
        writer.async { [self] in
            lock.lock()
            let allowed = !session.truncated && !session.failed && session.bytes + data.count + 1 <= maximumBytes
            if !allowed { session.truncated = true; session.dropped += 1 }
            lock.unlock()
            if allowed {
                do {
                    guard let handle = session.handle else { throw CocoaError(.fileWriteUnknown) }
                    try handle.write(contentsOf: data + Data([10]))
                    session.bytes += data.count + 1
                } catch { markFailed(session) }
            }
            lock.lock(); session.pending -= 1; lock.unlock()
        }
    }

    public func end(reason: String) {
        lock.lock()
        guard let session = current else { lock.unlock(); return }
        recordLocked("session.end", session: session, metrics: ["reason": .string(reason), "completed": .bool(true)])
        current = nil
        writer.async { [self] in
            session.timer?.cancel(); session.timer = nil
            flush(session)
            try? session.handle?.close()
            session.handle = nil; session.closed = true
        }
        lock.unlock()
    }

    /// Export all retained sessions; an unfinished session stays explicitly unfinished.
    public func export() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            let retained = sessions
            writer.async { [self] in
                do {
                    for session in retained where !session.closed { flush(session) }
                    lock.lock(); let failed = storageFailed; lock.unlock()
                    guard !failed else { throw CocoaError(.fileWriteUnknown) }
                    var data = Data()
                    for url in try journalFiles() {
                        data.append(try Data(contentsOf: url))
                        // Missing status after process death is intentionally not fabricated.
                        if let status = try? Data(contentsOf: url.appendingPathExtension("status")) { data.append(status) }
                    }
                    continuation.resume(returning: data)
                } catch { continuation.resume(throwing: error) }
            }
            lock.unlock()
        }
    }

    private func journal(_ session: Session) -> URL { directory.appendingPathComponent(session.id + ".jsonl") }

    private func journalFiles() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
            .filter { $0.pathExtension == "jsonl" }
            .sorted { (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast <
                (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast }
    }

    private func flush(_ session: Session) {
        lock.lock()
        let status: [String: JSONValue] = [
            "schemaVersion": .number(1), "sessionId": .string(session.id),
            "eventSeq": .number(Double(session.sequence)), "monotonicMs": .number(session.lastMilliseconds),
            "source": .string("ios"), "event": .string("trace.status"),
            "metrics": .object(["droppedEvents": .number(Double(session.dropped)),
                "truncated": .bool(session.truncated), "writeFailed": .bool(session.failed)])
        ]
        lock.unlock()
        do {
            try session.handle?.synchronize()
            let data = try JSONEncoder().encode(status) + Data([10])
            try data.write(to: journal(session).appendingPathExtension("status"), options: .atomic)
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: journal(session).appendingPathExtension("status").path)
            #endif
        } catch { markFailed(session) }
    }

    private func markFailed(_ session: Session) {
        lock.lock(); session.failed = true; storageFailed = true; lock.unlock()
    }
}
