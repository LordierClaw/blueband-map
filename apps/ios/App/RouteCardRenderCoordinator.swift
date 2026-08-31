import Foundation
import BlueBandCore
import BlueBandMapCore

protocol RouteCardSessionSending: Sendable {
    @discardableResult
    func sendAwaitingAcknowledgement(topic: String, body: [String: JSONValue]) async throws -> String
}

struct RouteCardRenderDiagnostics: Sendable {
    var gpsWaitMilliseconds = 0
    var routeRequestMilliseconds = 0
    var styleLoadMilliseconds = 0
    var snapshotMilliseconds = 0
    var paletteReductionMilliseconds = 0
    var paletteSize = 0
    var retainedFillLayers = 0
    var retainedLineLayers = 0
    var retainedSymbolLayers = 0
    var cacheState = "unknown"
}

struct BandSessionRouteCardSender: RouteCardSessionSending, Sendable {
    let session: BandSession

    @discardableResult
    func sendAwaitingAcknowledgement(topic: String, body: [String: JSONValue]) async throws -> String {
        try await session.sendAwaitingAcknowledgement(topic: topic, body: body)
    }
}

@MainActor
final class RouteCardRenderCoordinator {
    private enum PrepareResponse: Sendable {
        case ready(RouteCardBandReady)
        case reject(String)
    }

    private enum TransferPhase: Sendable {
        case preparing
        case transferring
        case awaitingFinalAcknowledgement
        case waitingForBand
    }

    private struct RouteCardBandReady: Sendable {
        let runID: String
        let sceneID: String
        let renderer: RenderKind
        let formatVersion: Int
        let width: Int
        let height: Int
        let bytes: Int
        let primitives: Int
    }

    private struct RouteCardBandResult: Sendable {
        let runID: String
        let sceneID: String
        let renderer: RenderKind
        let formatVersion: Int
        let success: Bool
        let bytes: Int
        let primitives: Int
        let renderMilliseconds: Int
        let prepareMilliseconds: Int
        let validateMilliseconds: Int
        let hashPrefix: String?
        let errorCode: String?
    }

    private struct PendingTransfer: Sendable {
        let token: UUID
        let mode: RouteCardMode
        let runID: String
        let sceneID: String
        let asset: RenderAsset
        let steps: [RenderTransferStep]
        var phase: TransferPhase
        var bufferedPrepareResponse: PrepareResponse?
        var bufferedResult: RouteCardBandResult?
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
        let diagnostics: RouteCardRenderDiagnostics
        var bandWriteMilliseconds = 0
        var bandDecodeMilliseconds = 0
        var bandPublicationMilliseconds = 0
    }

    let session: any RouteCardSessionSending
    let clock: any BlueBandClock
    let resultTimeout: Duration
    let transferWindow: Int
    let runIDGenerator: @Sendable () -> String
    let sceneIDGenerator: @Sendable () -> String

    private(set) var state: RouteCardTransferState = .idle
    private(set) var requiresReconnect = false
    private(set) var lastRunRecord: RenderRunRecord?
    private(set) var lastDisplayedSceneID: String?

    var failureCode: String? {
        guard case let .failed(_, code) = state else { return nil }
        return code
    }

    private var operationToken: UUID?
    private var operationTask: Task<Void, Never>?
    private var pending: PendingTransfer?
    private var runContext: RunContext?
    private var prepareContinuation: CheckedContinuation<PrepareResponse?, Never>?
    private var resultContinuation: CheckedContinuation<RouteCardBandResult?, Never>?
    private var resultTimeoutTask: Task<Void, Never>?
    private var prepareTimeoutTask: Task<Void, Never>?
    private var disconnectObserved = false

    init(
        session: any RouteCardSessionSending,
        clock: any BlueBandClock = ContinuousBlueBandClock(),
        resultTimeout: Duration = .seconds(15),
        transferWindow: Int = 2,
        runIDGenerator: @escaping @Sendable () -> String = { RouteCardRenderCoordinator.makeRunID() },
        sceneIDGenerator: @escaping @Sendable () -> String = { RouteCardRenderCoordinator.makeSceneID() }
    ) {
        self.session = session
        self.clock = clock
        self.resultTimeout = resultTimeout
        precondition([1, 2, 4].contains(transferWindow))
        self.transferWindow = transferWindow
        self.runIDGenerator = runIDGenerator
        self.sceneIDGenerator = sceneIDGenerator
    }

    func start(
        asset: RenderAsset,
        diagnostics: RouteCardRenderDiagnostics = .init(),
        preview: RenderNavigationPreview? = nil
    ) async {
        let mode = RouteCardMode.routeCard
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
            startedMilliseconds: Self.nowMilliseconds(),
            diagnostics: diagnostics
        )
        state = .fetching(mode: mode)
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.perform(
                token: token,
                mode: mode,
                asset: asset,
                runID: runID,
                sceneID: sceneID,
                preview: preview
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

    func failBeforeStart(mode: RouteCardMode, code: String) {
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
        if !reconnect, let pending {
            let session = session
            Task {
                _ = try? await session.sendAwaitingAcknowledgement(
                    topic: "render.cancel",
                    body: ["runId": .string(pending.runID), "sceneId": .string(pending.sceneID)]
                )
            }
        }
        finish(code: "TRANSFER_CANCELLED", requiresReconnect: reconnect)
    }

    private func perform(
        token: UUID,
        mode: RouteCardMode,
        asset: RenderAsset,
        runID: String,
        sceneID: String,
        preview: RenderNavigationPreview?
    ) async {
        guard ownsLive(token) else { return }
        guard assetMatchesMode(asset, mode: mode) else {
            finishOwned(code: "ASSET_INVALID", token: token, requiresReconnect: false)
            return
        }
        runContext?.asset = asset

        let validationStarted = Self.nowMilliseconds()
        let prepare: RenderPrepareBody
        let steps: [RenderTransferStep]
        do {
            prepare = try RenderPrepareBody(runID: runID, sceneID: sceneID, asset: asset, preview: preview)
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

        guard let begin = steps.first, let end = steps.last else {
            finishOwned(code: "ASSET_INVALID", token: token, requiresReconnect: false)
            return
        }
        let chunks = Array(steps.dropFirst().dropLast())
        state = .transferring(mode: mode, completed: 0, total: steps.count)
        runContext?.transferStartedMilliseconds = Self.nowMilliseconds()
        recordEvent("transfer-started")
        do {
            try await send(begin)
            guard ownsLive(token) else { return }
            state = .transferring(mode: mode, completed: 1, total: steps.count)

            var completed = 1
            try await withThrowingTaskGroup(of: Int.self) { group in
                var next = 0
                func addNext() {
                    let step = chunks[next]
                    next += 1
                    let session = session
                    group.addTask {
                        let started = Self.nowMilliseconds()
                        _ = try await session.sendAwaitingAcknowledgement(topic: step.topic, body: step.body)
                        return started
                    }
                }
                while next < min(transferWindow, chunks.count) { addNext() }
                while let started = try await group.next() {
                    recordAck(started: started)
                    completed += 1
                    state = .transferring(mode: mode, completed: completed, total: steps.count)
                    if next < chunks.count { addNext() }
                }
            }

            guard ownsLive(token), var current = pending, current.token == token else { return }
            current.phase = .awaitingFinalAcknowledgement
            pending = current
            try await send(end)
            state = .transferring(mode: mode, completed: steps.count, total: steps.count)
        } catch {
            finishOwned(code: transferCode(for: error), token: token, requiresReconnect: true)
            return
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
        let ready = RouteCardBandReady(
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
            resumePrepare(with: .ready(ready))
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
            resumePrepare(with: .reject(code))
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

    private func handleResult(_ result: RouteCardBandResult, token: UUID) {
        guard ownsLive(token), let pending, pending.token == token else { return }
        if let mismatch = resultMetadataMismatchCode(result, asset: pending.asset) {
            finishOwned(code: mismatch, token: token, requiresReconnect: true)
            return
        }
        if result.success {
            resultTimeoutTask?.cancel()
            resultTimeoutTask = nil
            lastDisplayedSceneID = pending.sceneID
            runContext?.renderMilliseconds = result.renderMilliseconds
            runContext?.bandWriteMilliseconds = result.prepareMilliseconds
            runContext?.bandDecodeMilliseconds = result.validateMilliseconds
            runContext?.bandPublicationMilliseconds = result.renderMilliseconds
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

    private func resultMetadataMismatchCode(_ result: RouteCardBandResult, asset: RenderAsset) -> String? {
        if result.renderer != asset.kind { return "RESULT_RENDERER_MISMATCH" }
        if result.formatVersion != asset.formatVersion { return "RESULT_FORMAT_MISMATCH" }
        if result.bytes != asset.byteCount { return "RESULT_BYTES_MISMATCH" }
        if result.primitives != asset.primitives { return "RESULT_PRIMITIVES_MISMATCH" }
        if let prefix = result.hashPrefix, prefix != String(asset.sha256.prefix(8)) {
            return "RESULT_HASH_MISMATCH"
        }
        return nil
    }

    private func waitForPrepareResponse(token: UUID) async -> PrepareResponse? {
        schedulePrepareTimeout(token: token)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<PrepareResponse?, Never>) in
                guard ownsLive(token), let pending, pending.token == token else {
                    continuation.resume(returning: nil)
                    return
                }
                if let buffered = pending.bufferedPrepareResponse {
                    prepareTimeoutTask?.cancel()
                    prepareTimeoutTask = nil
                    self.pending?.bufferedPrepareResponse = nil
                    continuation.resume(returning: buffered)
                } else {
                    prepareContinuation = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finishOwned(code: "TRANSFER_CANCELLED", token: token, requiresReconnect: false)
            }
        }
    }

    private func waitForResult(token: UUID) async -> RouteCardBandResult? {
        scheduleResultTimeout(token: token)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<RouteCardBandResult?, Never>) in
                guard ownsLive(token), let pending, pending.token == token else {
                    continuation.resume(returning: nil)
                    return
                }
                if let buffered = pending.bufferedResult {
                    resultTimeoutTask?.cancel()
                    resultTimeoutTask = nil
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

    private func schedulePrepareTimeout(token: UUID) {
        prepareTimeoutTask?.cancel()
        let clock = clock
        let timeout = resultTimeout
        prepareTimeoutTask = Task { @MainActor [weak self] in
            do { try await clock.sleep(for: timeout) }
            catch { return }
            guard !Task.isCancelled, let self, self.ownsLive(token) else { return }
            self.finishOwned(code: "ASSET_READY_TIMEOUT", token: token, requiresReconnect: true)
        }
    }

    private func finishOwned(code: String, token: UUID, requiresReconnect: Bool) {
        guard operationToken == token else { return }
        finish(code: code, requiresReconnect: requiresReconnect)
    }

    private func finish(code: String, requiresReconnect: Bool) {
        guard let token = operationToken, runContext != nil else { return }
        if requiresReconnect { self.requiresReconnect = true }
        let failedMode = pending?.mode ?? .routeCard
        state = .failed(mode: failedMode, code: code)
        prepareTimeoutTask?.cancel()
        prepareTimeoutTask = nil
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
            providerMilliseconds: max(context.providerMilliseconds, context.diagnostics.routeRequestMilliseconds),
            prepareMilliseconds: context.prepareMilliseconds,
            transferMilliseconds: context.transferMilliseconds,
            validateMilliseconds: context.validateMilliseconds,
            renderMilliseconds: context.renderMilliseconds,
            bytes: context.asset?.byteCount ?? 0,
            chunks: context.chunks,
            retries: 0,
            primitives: context.asset?.primitives ?? 0,
            providerCalls: context.diagnostics.routeRequestMilliseconds > 0 ? 1 : context.providerCalls,
            gpsWaitMilliseconds: context.diagnostics.gpsWaitMilliseconds,
            routeRequestMilliseconds: context.diagnostics.routeRequestMilliseconds,
            styleLoadMilliseconds: context.diagnostics.styleLoadMilliseconds,
            snapshotMilliseconds: context.diagnostics.snapshotMilliseconds,
            paletteReductionMilliseconds: context.diagnostics.paletteReductionMilliseconds,
            transferPrepareMilliseconds: context.validateMilliseconds,
            bandWriteMilliseconds: context.bandWriteMilliseconds,
            bandDecodeMilliseconds: context.bandDecodeMilliseconds,
            bandPublicationMilliseconds: context.bandPublicationMilliseconds,
            paletteSize: context.diagnostics.paletteSize,
            retainedFillLayers: context.diagnostics.retainedFillLayers,
            retainedLineLayers: context.diagnostics.retainedLineLayers,
            retainedSymbolLayers: context.diagnostics.retainedSymbolLayers,
            transferWindow: transferWindow,
            cacheState: context.diagnostics.cacheState,
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

    private func send(_ step: RenderTransferStep) async throws {
        let started = Self.nowMilliseconds()
        _ = try await session.sendAwaitingAcknowledgement(topic: step.topic, body: step.body)
        recordAck(started: started)
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
        prepareTimeoutTask?.cancel()
        prepareTimeoutTask = nil
        guard let continuation = prepareContinuation else { return }
        prepareContinuation = nil
        continuation.resume(returning: response)
    }

    private func resumeResult(with result: RouteCardBandResult?) {
        guard let continuation = resultContinuation else { return }
        resultContinuation = nil
        continuation.resume(returning: result)
    }

    private func ownsLive(_ token: UUID) -> Bool {
        operationToken == token && runContext?.token == token
    }

    private func readyMatches(_ ready: RouteCardBandReady, prepare: RenderPrepareBody) -> Bool {
        ready.runID == prepare.runID && ready.sceneID == prepare.sceneID &&
            ready.renderer == prepare.renderer && ready.formatVersion == prepare.formatVersion &&
            ready.width == prepare.width && ready.height == prepare.height &&
            ready.bytes == prepare.bytes && ready.primitives == prepare.primitives
    }

    private func parseResult(_ body: [String: JSONValue], pending: PendingTransfer) -> RouteCardBandResult? {
        guard let runID = string(body, key: "runId"), runID == pending.runID,
              let sceneID = string(body, key: "sceneId"), sceneID == pending.sceneID,
              let renderer = renderKind(body, key: "renderer"),
              let formatVersion = integer(body, key: "formatVersion"),
              let status = string(body, key: "status"),
              status == "ok" || status == "error",
              let bytes = integer(body, key: "bytes"),
              let primitives = integer(body, key: "primitives"),
              let renderMilliseconds = integer(body, key: "renderMs"),
              let prepareMilliseconds = integer(body, key: "prepareMs"),
              let validateMilliseconds = integer(body, key: "validateMs"),
              renderMilliseconds >= 0, prepareMilliseconds >= 0, validateMilliseconds >= 0 else { return nil }
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
        return RouteCardBandResult(
            runID: runID,
            sceneID: sceneID,
            renderer: renderer,
            formatVersion: formatVersion,
            success: status == "ok",
            bytes: bytes,
            primitives: primitives,
            renderMilliseconds: renderMilliseconds,
            prepareMilliseconds: prepareMilliseconds,
            validateMilliseconds: validateMilliseconds,
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

    private func assetMatchesMode(_ asset: RenderAsset, mode: RouteCardMode) -> Bool {
        asset.kind == mode.renderer && asset.primitives == 0
    }

    nonisolated static func makeRunID() -> String {
        "nav-run-" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16))
    }

    nonisolated static func makeSceneID() -> String {
        "scene-" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16))
    }

    nonisolated private static func nowMilliseconds() -> Int {
        Int(Date().timeIntervalSince1970 * 1_000)
    }
}
