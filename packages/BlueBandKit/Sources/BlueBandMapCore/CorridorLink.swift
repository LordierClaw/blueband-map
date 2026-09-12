import Foundation
import Crypto
import BlueBandCore

/// App-envelope control plane; proprietary transport framing remains owned by BandSession.
@MainActor
public final class CorridorLink {
    public typealias Send = @MainActor @Sendable (String, [String: JSONValue]) async throws -> String
    public private(set) var epoch: String?
    public private(set) var ready = false
    public private(set) var cachedCells = Set<String>()
    public private(set) var displayedViewport: CorridorViewport?
    public private(set) var displayedSequence = -1
    public private(set) var failure: String?
    public var onDisplay: ((CorridorViewport, Int) -> Void)?
    private let send: Send
    private let timeout: Duration
    private var scene = ""
    private var sequence = 0
    private var views: [Int: CorridorViewport] = [:]
    private var cellInFlight: String?
    private var cellReply: (request: String, status: String)?
    private var hashes: [String: String] = [:]

    public init(timeout: Duration = .seconds(3), send: @escaping Send) {
        self.timeout = timeout
        self.send = send
    }

    public func reset() {
        epoch = nil; ready = false; scene = ""; failure = nil
        cachedCells.removeAll(); hashes.removeAll(); views.removeAll()
        displayedViewport = nil; displayedSequence = -1; sequence = 0
        cellInFlight = nil; cellReply = nil
    }

    public func close() async {
        let old = epoch
        reset()
        if let old { _ = try? await send("map.stream.close", ["epoch": .string(old)]) }
    }

    public func open(scene: String) async -> Bool {
        await close()
        guard RenderProtocol.isValidIdentifier(scene), !Task.isCancelled else { return false }
        let owned = "c-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).lowercased()
        epoch = owned; self.scene = scene
        do {
            _ = try await send("map.stream.open", ["epoch": .string(owned), "scene": .string(scene), "version": .number(1)])
            let confirmed = await wait(epoch: owned) { self.ready }
            if !confirmed, epoch == owned { fail("unsupportedOrTimeout") }
            return confirmed
        } catch { if epoch == owned { fail("openFailed") }; return false }
    }

    public func sendCell(_ cell: CorridorCell, data: Data) async -> Bool {
        guard ready, let owned = epoch, cellInFlight == nil,
              Self.validCell(cell.key), (33...8192).contains(data.count) else { return false }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if hashes[cell.key] == hash { return true }
        cellInFlight = cell.key; cellReply = nil
        defer { if epoch == owned { cellInFlight = nil; cellReply = nil } }
        let identity: [String: JSONValue] = ["epoch": .string(owned), "cell": .string(cell.key)]
        do {
            var begin = identity
            begin["bytes"] = .number(Double(data.count))
            begin["sha256"] = .string(hash)
            let beginID = try await send("map.cell.begin", begin)
            guard epoch == owned, ready, cellReply?.status != "error" else { return false }
            if cellReply?.request == beginID, cellReply?.status == "stored" {
                cachedCells.insert(cell.key)
                hashes[cell.key] = hash
                return checkCacheBound()
            }
            let offsets = Array(stride(from: 0, to: data.count, by: 216)), send = self.send
            for start in stride(from: 0, to: offsets.count, by: 4) {
                try Task.checkCancellation()
                guard epoch == owned, ready else { return false }
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for offset in offsets[start..<min(start + 4, offsets.count)] {
                        var chunk = identity
                        chunk["offset"] = .number(Double(offset))
                        chunk["data"] = .string(data.subdata(in: offset..<min(offset + 216, data.count)).base64EncodedString())
                        let body = chunk
                        group.addTask { _ = try await send("map.cell.chunk", body) }
                    }
                    try await group.waitForAll()
                }
            }
            guard epoch == owned, ready else { return false }
            let request = try await send("map.cell.end", identity)
            let stored = await wait(epoch: owned) { self.cellReply?.request == request && self.cellReply?.status == "stored" }
            guard stored, ready else { if epoch == owned { fail("cellTimeout") }; return false }
            cachedCells.insert(cell.key)
            hashes[cell.key] = hash
            return checkCacheBound()
        } catch { if epoch == owned { fail("cellSendFailed") }; return false }
    }

    @discardableResult
    public func sendView(_ viewport: CorridorViewport) async -> Bool {
        guard ready, let owned = epoch, sequence < 2147483647 else { return false }
        sequence += 1
        let seq = sequence
        views[seq] = viewport
        views = views.filter { $0.key >= seq - 8 }
        do {
            _ = try await send("map.stream.view", ["epoch": .string(owned), "seq": .number(Double(seq)),
                "x": .number(Double(viewport.x)), "y": .number(Double(viewport.y))])
            return epoch == owned && ready
        } catch { if epoch == owned { fail("viewSendFailed") }; return false }
    }

    public func consume(_ envelope: ApplicationEnvelope) {
        guard envelope.src == .band, envelope.type == .message, let body = envelope.body,
              let owned = epoch, body["epoch"] == .string(owned) else { return }
        switch envelope.topic {
        case "map.stream.ready":
            guard body["scene"] == .string(scene), body["version"] == .number(1),
                  body["cellSize"] == .number(128), body["maximumFiles"] == .number(30),
                  body["maximumResident"] == .number(24), failure == nil else { return }
            ready = true
        case "map.cell.result":
            guard ready, body["cell"] == cellInFlight.map(JSONValue.string),
                  case let .string(request)? = body["request"], RenderProtocol.isValidIdentifier(request),
                  case let .string(status)? = body["status"], ["stored", "error"].contains(status),
                  let evicted = Self.cellList(body["evicted"], maximum: 1) else { return }
            cachedCells.subtract(evicted)
            for key in evicted { hashes.removeValue(forKey: key) }
            cellReply = (request, status)
            if status == "error" { fail("cellRejected") }
        case "map.stream.state":
            guard ready, case let .string(code)? = body["code"],
                  let missing = Self.cellList(body["missing"], maximum: 18) else { return }
            if code != "ok" { fail("viewRejected"); return }
            cachedCells.subtract(missing)
            for key in missing { hashes.removeValue(forKey: key) }
            guard case let .number(value)? = body["displayedSeq"], value.isFinite,
                  value.rounded() == value, value >= 0, value <= Double(sequence),
                  Int(value) > displayedSequence, let view = views[Int(value)] else { return }
            displayedViewport = view; displayedSequence = Int(value)
            views = views.filter { $0.key >= Int(value) }
            onDisplay?(view, Int(value))
        default: break
        }
    }

    private func fail(_ code: String) { ready = false; failure = code }

    private func checkCacheBound() -> Bool {
        if cachedCells.count > CorridorViewport.maximumFiles { fail("cacheBoundExceeded") }
        return ready
    }

    private func wait(epoch owned: String, until predicate: () -> Bool) async -> Bool {
        let clock = ContinuousClock(), deadline = ContinuousClock.now.advanced(by: timeout)
        while epoch == owned, failure == nil, !Task.isCancelled {
            if predicate() { return true }
            if clock.now >= deadline { return false }
            do { try await clock.sleep(for: .milliseconds(5)) } catch { return false }
        }
        return false
    }

    private static func cellList(_ value: JSONValue?, maximum: Int) -> [String]? {
        guard case let .array(items)? = value, items.count <= maximum else { return nil }
        var result = [String]()
        for item in items {
            guard case let .string(key) = item, validCell(key), !result.contains(key) else { return nil }
            result.append(key)
        }
        return result
    }

    private static func validCell(_ key: String) -> Bool {
        let parts = key.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, key.utf8.count <= 9 else { return false }
        return parts.allSatisfy { part in
            guard let n = Int(part), (-261...261).contains(n) else { return false }
            return String(n) == part
        }
    }
}
