import Foundation
import BlueBandCore
import BlueBandMapCore

protocol H1SessionSending: Sendable {
    @discardableResult
    func sendAwaitingAcknowledgement(topic: String, body: [String: JSONValue]) async throws -> String
}

struct BandSessionH1Sender: H1SessionSending, Sendable {
    let session: BandSession

    @discardableResult
    func sendAwaitingAcknowledgement(topic: String, body: [String: JSONValue]) async throws -> String {
        try await session.sendAwaitingAcknowledgement(topic: topic, body: body)
    }
}

typealias H1AssetProvider = @Sendable (
    _ mode: H1TestMode,
    _ serviceKey: String?,
    _ tileMapKey: String?
) async throws -> RenderAsset

@MainActor
final class H1RenderCoordinator {
    private enum PrepareResponse: Sendable {
        case ready(H1BandReady)
        case reject(String)
    }

    private enum TransferPhase: Sendable {
        case preparing
        case transferring
        case awaitingFinalAcknowledgement
        case waitingForBand
    }

    private struct H1BandReady: Sendable {
        let runID: String
        let sceneID: String
        let renderer: RenderKind
        let formatVersion: Int
        let width: Int
        let height: Int
        let bytes: Int
        let primitives: Int
    }

    private struct H1BandResult: Sendable {
        let runID: String
        let sceneID: String
        let renderer: RenderKind
        let formatVersion: Int
        let success: Bool
        let bytes: Int
        let primitives: Int
        let renderMilliseconds: Int
        let hashPrefix: String?
        let errorCode: String?
    }

    private struct PendingTransfer: Sendable {
        let token: UUID
        let mode: H1TestMode
        let runID: String
        let sceneID: String
        let asset: RenderAsset
        let steps: [RenderTransferStep]
        var phase: TransferPhase
        var bufferedPrepareResponse: PrepareResponse?
        var bufferedResult: H1BandResult?
    }

    private struct RunContext {
        let identity: RenderRunIdentity
        let token: UUID
        let startedMilliseconds: Int
        var asset: RenderAsset?
        var providerMilliseconds = 0
        var prepareMilliseconds = 0
        var transferMilliseconds = 0
        var validateMilliseconds = 0
        var renderMilliseconds = 0
        var transferStartedMilliseconds = 0
        var validationStartedMilliseconds = 0
        var validationFinishedMilliseconds = 0
        var chunks = 0
        var providerCalls = 0
        var ackDurations: [Int] = []
        var events: [RenderRunEvent] = []
        var nextEventSequence = 0
    }

    let session: any H1SessionSending
    let assetProvider: H1AssetProvider
    let clock: any BlueBandClock
    let resultTimeout: Duration
    let runIDGenerator: @Sendable () -> String
    let sceneIDGenerator: @Sendable () -> String

    private(set) var state: H1State = .idle
    private(set) var requiresReconnect = false
    private(set) var lastRunRecord: RenderRunRecord?

    private var operationToken: UUID?
    private var operationTask: Task<Void, Never>?
    private var pending: PendingTransfer?
    private var runContext: RunContext?
    private var prepareContinuation: CheckedContinuation<PrepareResponse?, Never>?
    private var resultContinuation: CheckedContinuation<H1BandResult?, Never>?
    private var resultTimeoutTask: Task<Void, Never>?
    private var disconnectObserved = false

    init(
        session: any H1SessionSending,
        assetProvider: @escaping H1AssetProvider,
        clock: any BlueBandClock = ContinuousBlueBandClock(),
        resultTimeout: Duration = .seconds(15),
        runIDGenerator: @escaping @Sendable () -> String = { H1RenderCoordinator.makeRunID() },
        sceneIDGenerator: @escaping @Sendable () -> String = { H1RenderCoordinator.makeSceneID() }
    ) {
        self.session = session
        self.assetProvider = assetProvider
        self.clock = clock
        self.resultTimeout = resultTimeout
        self.runIDGenerator = runIDGenerator
        self.sceneIDGenerator = sceneIDGenerator
    }

    func start(mode: H1TestMode, serviceKey: String? = nil, tileMapKey: String? = nil) async {
        guard operationToken == nil else { return }
        guard !requiresReconnect else {
            state = .failed(mode: mode, code: "TRANSFER_RECONNECT_REQUIRED")
            return
        }

        let token = UUID()
        let runID = runIDGenerator()
        let sceneID = sceneIDGenerator()
        guard let identity = try? RenderRunIdentity(
            runID: runID,
            sceneID: sceneID,
            renderer: mode.renderer,
            formatVersion: RenderProtocol.formatVersion,
            width: RenderProtocol.viewportWidth,
            height: RenderProtocol.viewportHeight,
            startedAt: "t\(Self.nowMilliseconds())"
        ) else {
            state = .failed(mode: mode, code: "ASSET_INVALID")
            return
        }

        operationToken = token
        runContext = RunContext(
            identity: identity,
            token: token,
            startedMilliseconds: Self.nowMilliseconds()
        )
        state = .fetching(mode: mode)
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.perform(
                token: token,
                mode: mode,
                runID: runID,
                sceneID: sceneID,
                serviceKey: serviceKey,
                tileMapKey: tileMapKey
            )
        }
        operationTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if operationToken == token {
            operationTask = nil
            operationToken = nil
            pending = nil
            runContext = nil
        }
    }

    func consume(_ envelope: ApplicationEnvelope) {
        guard envelope.src == .band,
              envelope.type == .message,
              let topic = envelope.topic,
              let body = envelope.body,
              let pending,
              pending.token == operationToken else { return }

        switch topic {
        case RenderProtocol.readyTopic:
            consumeReady(body, pending: pending)
        case RenderProtocol.rejectTopic:
            consumeReject(body, pending: pending)
        case RenderProtocol.resultTopic:
            consumeResult(body, pending: pending)
        default:
            return
        }
    }

    func disconnected() {
        disconnectObserved = true
        if operationToken != nil {
            finish(code: "TRANSFER_DISCONNECTED", requiresReconnect: true)
        }
    }

    func reconnected() {
        guard disconnectObserved else { return }
        disconnectObserved = false
        requiresReconnect = false
    }

    func failBeforeStart(mode: H1TestMode, code: String) {
        guard operationToken == nil else { return }
        state = .failed(mode: mode, code: code)
    }

    func cancel() {
        guard operationToken != nil else { return }
        let reconnect: Bool
        if let phase = pending?.phase {
            reconnect = phase != .preparing
        } else {
            reconnect = false
        }
        finish(code: "TRANSFER_CANCELLED", requiresReconnect: reconnect)
    }

    private func perform(
        token: UUID,
        mode: H1TestMode,
        runID: String,
        sceneID: String,
        serviceKey: String?,
        tileMapKey: String?
    ) async {
        guard ownsLive(token) else { return }
        let providerStarted = Self.nowMilliseconds()
        let asset: RenderAsset
        do {
            runContext?.providerCalls += 1
            asset = try await assetProvider(mode, serviceKey, tileMapKey)
        } catch {
            finishOwned(code: providerCode(for: error), token: token, requiresReconnect: false)
            return
        }
        guard ownsLive(token) else { return }
        guard assetMatchesMode(asset, mode: mode) else {
            finishOwned(code: "ASSET_INVALID", token: token, requiresReconnect: false)
            return
        }
        runContext?.providerMilliseconds = max(0, Self.nowMilliseconds() - providerStarted)
        runContext?.asset = asset

        let validationStarted = Self.nowMilliseconds()
        let prepare: RenderPrepareBody
        let steps: [RenderTransferStep]
        do {
            prepare = try RenderPrepareBody(runID: runID, sceneID: sceneID, asset: asset)
            steps = try RenderTransferPlan.make(asset: asset, runID: runID, sceneID: sceneID)
        } catch {
            finishOwned(code: "ASSET_INVALID", token: token, requiresReconnect: false)
            return
        }
        runContext?.validationStartedMilliseconds = validationStarted
        runContext?.validationFinishedMilliseconds = Self.nowMilliseconds()
        runContext?.validateMilliseconds = max(0, Self.nowMilliseconds() - validationStarted)
        runContext?.chunks = steps.count
        recordEvent("asset-validated")

        pending = PendingTransfer(
            token: token,
            mode: mode,
            runID: runID,
            sceneID: sceneID,
            asset: asset,
            steps: steps,
            phase: .preparing,
            bufferedPrepareResponse: nil,
            bufferedResult: nil
        )
        state = .preparing(mode: mode, runID: runID)
        let prepareStarted = Self.nowMilliseconds()
        do {
            _ = try await session.sendAwaitingAcknowledgement(
                topic: RenderProtocol.prepareTopic,
                body: prepare.jsonBody()
            )
        } catch {
            finishOwned(code: transferCode(for: error), token: token, requiresReconnect: true)
            return
        }
        recordAck(started: prepareStarted)
        guard ownsLive(token) else { return }

        let prepareResponse = await waitForPrepareResponse(token: token)
        guard ownsLive(token), let prepareResponse else { return }
        switch prepareResponse {
        case let .reject(code):
            finishOwned(code: code, token: token, requiresReconnect: false)
            return
        case let .ready(ready):
            guard readyMatches(ready, prepare: prepare) else {
                finishOwned(code: "ASSET_RESULT_INVALID", token: token, requiresReconnect: true)
                return
            }
        }

        state = .transferring(mode: mode, completed: 0, total: steps.count)
        runContext?.transferStartedMilliseconds = Self.nowMilliseconds()
        recordEvent("transfer-started")
        for (index, step) in steps.enumerated() {
            guard ownsLive(token), var current = pending, current.token == token else { return }
            let isFinal = index == steps.count - 1
            current.phase = isFinal ? .awaitingFinalAcknowledgement : .transferring
            pending = current
            let sendStarted = Self.nowMilliseconds()
            do {
                _ = try await session.sendAwaitingAcknowledgement(topic: step.topic, body: step.body)
            } catch {
                finishOwned(code: transferCode(for: error), token: token, requiresReconnect: true)
                return
            }
            recordAck(started: sendStarted)
            guard ownsLive(token), let current = pending, current.token == token else { return }
            state = .transferring(mode: mode, completed: index + 1, total: steps.count)
        }

        guard ownsLive(token), var waiting = pending, waiting.token == token else { return }
        waiting.phase = .waitingForBand
        pending = waiting
        let now = Self.nowMilliseconds()
        let transferStarted = runContext?.transferStartedMilliseconds ?? now
        runContext?.transferMilliseconds = max(0, now - transferStarted)
        state = .waitingForBand(mode: mode, runID: runID, sceneID: sceneID)
        recordEvent("transfer-complete")

        if let buffered = pending?.bufferedResult {
            pending?.bufferedResult = nil
            handleResult(buffered, token: token)
            return
        }
        let result = await waitForResult(token: token)
        guard ownsLive(token), let result else { return }
        handleResult(result, token: token)
    }

    private func consumeReady(_ body: [String: JSONValue], pending: PendingTransfer) {
        guard pending.phase == .preparing,
              let runID = string(body, key: "runId"),
              let sceneID = string(body, key: "sceneId"),
              runID == pending.runID,
              sceneID == pending.sceneID,
              let renderer = renderKind(body, key: "renderer"),
              let formatVersion = integer(body, key: "formatVersion"),
              let width = integer(body, key: "width"),
              let height = integer(body, key: "height"),
              let bytes = integer(body, key: "bytes"),
              let primitives = integer(body, key: "primitives") else {
            if string(body, key: "runId") == pending.runID { finish(code: "ASSET_RESULT_INVALID", requiresReconnect: true) }
            return
        }
        let ready = H1BandReady(
            runID: runID,
            sceneID: sceneID,
            renderer: renderer,
            formatVersion: formatVersion,
            width: width,
            height: height,
            bytes: bytes,
            primitives: primitives
        )
        if prepareContinuation != nil {
            prepareContinuation?.resume(returning: .ready(ready))
            prepareContinuation = nil
        } else {
            self.pending?.bufferedPrepareResponse = .ready(ready)
        }
    }

    private func consumeReject(_ body: [String: JSONValue], pending: PendingTransfer) {
        guard pending.phase == .preparing,
              let runID = string(body, key: "runId"),
              let sceneID = string(body, key: "sceneId"),
              runID == pending.runID,
              sceneID == pending.sceneID,
              let code = string(body, key: "code"),
              RenderRejectCode(rawValue: code) != nil else { return }
        if prepareContinuation != nil {
            prepareContinuation?.resume(returning: .reject(code))
            prepareContinuation = nil
        } else {
            self.pending?.bufferedPrepareResponse = .reject(code)
        }
    }

    private func consumeResult(_ body: [String: JSONValue], pending: PendingTransfer) {
        guard let result = parseResult(body, pending: pending) else {
            if string(body, key: "runId") == pending.runID {
                finish(code: "RESULT_SCHEMA_INVALID", requiresReconnect: true)
            }
            return
        }
        if result.success && pending.phase == .transferring {
            finish(code: "RESULT_EARLY", requiresReconnect: true)
        } else if pending.phase == .awaitingFinalAcknowledgement {
            self.pending?.bufferedResult = result
        } else if pending.phase == .waitingForBand, let token = operationToken {
            handleResult(result, token: token)
        } else if !result.success, let token = operationToken {
            handleResult(result, token: token)
        }
    }

    private func handleResult(_ result: H1BandResult, token: UUID) {
        guard ownsLive(token), let pending, pending.token == token else { return }
        guard result.renderer == pending.asset.kind,
              result.formatVersion == pending.asset.formatVersion,
              result.bytes == pending.asset.byteCount,
              result.primitives == pending.asset.primitives,
              result.hashPrefix == nil || result.hashPrefix == String(pending.asset.sha256.prefix(8)) else {
            finishOwned(code: "RESULT_METADATA_INVALID", token: token, requiresReconnect: true)
            return
        }
        if result.success {
            runContext?.renderMilliseconds = result.renderMilliseconds
            state = .displayed(
                mode: pending.mode,
                runID: pending.runID,
                hashPrefix: String(pending.asset.sha256.prefix(8))
            )
            recordEvent("displayed")
            finishRun("displayed")
        } else {
            guard let code = result.errorCode, isSafeCode(code) else {
                finishOwned(code: "RESULT_SCHEMA_INVALID", token: token, requiresReconnect: true)
                return
            }
            guard code.hasPrefix("ASSET_") else {
                finishOwned(code: "RESULT_SCHEMA_INVALID", token: token, requiresReconnect: true)
                return
            }
            finishOwned(code: code, token: token, requiresReconnect: false)
        }
    }

    private func waitForPrepareResponse(token: UUID) async -> PrepareResponse? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<PrepareResponse?, Never>) in
                guard ownsLive(token), let pending, pending.token == token else {
                    continuation.resume(returning: nil)
                    return
                }
                if let buffered = pending.bufferedPrepareResponse {
                    self.pending?.bufferedPrepareResponse = nil
                    continuation.resume(returning: buffered)
                } else {
                    prepareContinuation = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.resumePrepare(with: nil)
            }
        }
    }

    private func waitForResult(token: UUID) async -> H1BandResult? {
        scheduleResultTimeout(token: token)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<H1BandResult?, Never>) in
                guard ownsLive(token), let pending, pending.token == token else {
                    continuation.resume(returning: nil)
                    return
                }
                if let buffered = pending.bufferedResult {
                    self.pending?.bufferedResult = nil
                    continuation.resume(returning: buffered)
                } else {
                    resultContinuation = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.resumeResult(with: nil)
            }
        }
    }

    private func scheduleResultTimeout(token: UUID) {
        resultTimeoutTask?.cancel()
        let clock = clock
        let timeout = resultTimeout
        resultTimeoutTask = Task { @MainActor [weak self] in
            do { try await clock.sleep(for: timeout) }
            catch { return }
            guard !Task.isCancelled, let self, self.ownsLive(token) else { return }
            self.finishOwned(code: "ASSET_RESULT_TIMEOUT", token: token, requiresReconnect: true)
        }
    }

    private func finishOwned(code: String, token: UUID, requiresReconnect: Bool) {
        guard operationToken == token else { return }
        finish(code: code, requiresReconnect: requiresReconnect)
    }

    private func finish(code: String, requiresReconnect: Bool) {
        guard let token = operationToken, runContext != nil else { return }
        if requiresReconnect { self.requiresReconnect = true }
        let failedMode = pending?.mode ?? (
            runContext?.identity.renderer == .vector ? .vectorVietmap : .rasterBaseline
        )
        state = .failed(mode: failedMode, code: code)
        resultTimeoutTask?.cancel()
        resultTimeoutTask = nil
        resumePrepare(with: nil)
        resumeResult(with: nil)
        recordEvent(code.lowercased())
        finishRun(code)
        pending = nil
        operationTask?.cancel()
        _ = token
    }

    private func finishRun(_ terminalCode: String) {
        guard var context = runContext else { return }
        let now = Self.nowMilliseconds()
        let total = max(0, now - context.startedMilliseconds)
        if context.transferMilliseconds == 0, context.transferStartedMilliseconds > 0 {
            context.transferMilliseconds = max(0, now - context.transferStartedMilliseconds)
        }
        guard let metrics = try? RenderRunMetrics(
            totalMilliseconds: total,
            providerMilliseconds: context.providerMilliseconds,
            prepareMilliseconds: context.prepareMilliseconds,
            transferMilliseconds: context.transferMilliseconds,
            validateMilliseconds: context.validateMilliseconds,
            renderMilliseconds: context.renderMilliseconds,
            bytes: context.asset?.byteCount ?? 0,
            chunks: context.chunks,
            retries: 0,
            primitives: context.asset?.primitives ?? 0,
            providerCalls: context.providerCalls,
            ackDurationsMilliseconds: context.ackDurations,
            terminalCode: terminalCode
        ) else {
            runContext = nil
            return
        }
        let payloadSHA256 = context.asset?.sha256 ?? String(repeating: "0", count: 64)
        lastRunRecord = RenderRunRecord(
            identity: context.identity,
            events: context.events,
            metrics: metrics,
            payloadSHA256: payloadSHA256
        )
        runContext = nil
    }

    private func recordAck(started: Int) {
        guard var context = runContext else { return }
        context.ackDurations.append(max(0, Self.nowMilliseconds() - started))
        if context.ackDurations.count == 1 {
            context.prepareMilliseconds = context.ackDurations[0]
        }
        runContext = context
    }

    private func recordEvent(_ name: String) {
        guard var context = runContext,
              let event = try? RenderRunEvent(
                  sequence: context.nextEventSequence,
                  name: name,
                  milliseconds: max(0, Self.nowMilliseconds() - context.startedMilliseconds)
              ) else { return }
        context.events.append(event)
        context.nextEventSequence += 1
        runContext = context
    }

    private func resumePrepare(with response: PrepareResponse?) {
        guard let continuation = prepareContinuation else { return }
        prepareContinuation = nil
        continuation.resume(returning: response)
    }

    private func resumeResult(with result: H1BandResult?) {
        guard let continuation = resultContinuation else { return }
        resultContinuation = nil
        continuation.resume(returning: result)
    }

    private func ownsLive(_ token: UUID) -> Bool {
        operationToken == token && runContext?.token == token
    }

    private func readyMatches(_ ready: H1BandReady, prepare: RenderPrepareBody) -> Bool {
        ready.runID == prepare.runID && ready.sceneID == prepare.sceneID &&
            ready.renderer == prepare.renderer && ready.formatVersion == prepare.formatVersion &&
            ready.width == prepare.width && ready.height == prepare.height &&
            ready.bytes == prepare.bytes && ready.primitives == prepare.primitives
    }

    private func parseResult(_ body: [String: JSONValue], pending: PendingTransfer) -> H1BandResult? {
        guard let runID = string(body, key: "runId"), runID == pending.runID,
              let sceneID = string(body, key: "sceneId"), sceneID == pending.sceneID,
              let renderer = renderKind(body, key: "renderer"),
              let formatVersion = integer(body, key: "formatVersion"),
              let status = string(body, key: "status"),
              status == "ok" || status == "error",
              let bytes = integer(body, key: "bytes"),
              let primitives = integer(body, key: "primitives"),
              let renderMilliseconds = integer(body, key: "renderMs"),
              renderMilliseconds >= 0 else { return nil }
        let hashPrefix: String?
        switch body["sha256Prefix"] {
        case nil:
            hashPrefix = nil
        case let .string(value)?:
            hashPrefix = value
        default:
            return nil
        }
        let errorCode: String?
        switch body["errorCode"] {
        case nil:
            errorCode = nil
        case let .string(value)?:
            errorCode = value
        default:
            return nil
        }
        return H1BandResult(
            runID: runID,
            sceneID: sceneID,
            renderer: renderer,
            formatVersion: formatVersion,
            success: status == "ok",
            bytes: bytes,
            primitives: primitives,
            renderMilliseconds: renderMilliseconds,
            hashPrefix: hashPrefix,
            errorCode: errorCode
        )
    }

    private func renderKind(_ body: [String: JSONValue], key: String) -> RenderKind? {
        guard let value = string(body, key: key) else { return nil }
        return RenderKind(rawValue: value)
    }

    private func string(_ body: [String: JSONValue], key: String) -> String? {
        guard case let .string(value)? = body[key] else { return nil }
        return value
    }

    private func integer(_ body: [String: JSONValue], key: String) -> Int? {
        guard case let .number(value)? = body[key], value.isFinite,
              value.rounded(.towardZero) == value,
              value >= Double(Int.min), value <= Double(Int.max) else { return nil }
        return Int(value)
    }

    private func isSafeCode(_ value: String) -> Bool {
        guard (1...40).contains(value.utf8.count) else { return false }
        return value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || $0 == 95 || $0 == 45
        }
    }

    private func providerCode(for error: Swift.Error) -> String {
        switch error {
        case let error as VietmapStaticMapError:
            switch error {
            case .rateLimited: return "PROVIDER_RATE_LIMITED"
            case let .httpStatus(status): return providerHTTPCode(status)
            case .wrongContentType: return "PROVIDER_MIME"
            case .invalidRequest, .missingServiceKey: return "PROVIDER_REQUEST"
            }
        case let error as VietmapStyleError:
            switch error {
            case let .httpStatus(status): return providerHTTPCode(status)
            case .wrongContentType: return "PROVIDER_MIME"
            case .missingTileMapKey: return "TILEMAP_KEY_MISSING"
            case .invalidJSON, .missingTiles, .noRoadLayers: return "PROVIDER_DATA"
            default: return "PROVIDER_REQUEST"
            }
        case let error as H1AssetFactory.Error:
            switch error {
            case let .tileHTTPStatus(status): return providerHTTPCode(status)
            case .tileWrongContentType: return "PROVIDER_MIME"
            case .missingTileMapConfiguration: return "TILEMAP_KEY_MISSING"
            case .tileEmpty, .tileHasNoRoads: return "PROVIDER_DATA"
            }
        case is CancellationError:
            return "TRANSFER_CANCELLED"
        case is RenderAsset.Error, is MapAsset.Error, is RenderTransferPlan.Error:
            return "ASSET_INVALID"
        default:
            return "PROVIDER_REQUEST"
        }
    }

    private func providerHTTPCode(_ status: Int) -> String {
        (100...599).contains(status) ? "PROVIDER_HTTP_\(status)" : "PROVIDER_HTTP"
    }

    private func transferCode(for error: Swift.Error) -> String {
        switch error {
        case is CancellationError:
            return "TRANSFER_CANCELLED"
        case InterconnectDeliveryError.timeout:
            return "TRANSFER_TIMEOUT"
        case InterconnectDeliveryError.disconnected,
             BandSessionError.disconnected,
             BandSessionError.notConnected,
             InterconnectSession.Error.notReady:
            return "TRANSFER_DISCONNECTED"
        default:
            return "TRANSFER_FAILED"
        }
    }

    private func assetMatchesMode(_ asset: RenderAsset, mode: H1TestMode) -> Bool {
        guard asset.kind == mode.renderer else { return false }
        switch mode {
        case .vectorSynthetic8, .vectorSynthetic20, .vectorSynthetic40:
            return asset.primitives == mode.expectedPrimitives
        case .rasterBaseline, .rasterOptimized, .vectorVietmap:
            return true
        }
    }

    nonisolated static func makeRunID() -> String {
        "h1-run-" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16))
    }

    nonisolated static func makeSceneID() -> String {
        "scene-" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16))
    }

    nonisolated private static func nowMilliseconds() -> Int {
        Int(Date().timeIntervalSince1970 * 1_000)
    }
}
