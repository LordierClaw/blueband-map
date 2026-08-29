import Foundation
import XCTest
import BlueBandCore
import BlueBandCrypto
import BlueBandMapCore
import BlueBandProtocol
@testable import BlueBandMap

@MainActor
final class M1AppModelTests: XCTestCase {
    func testFixedM1ConfigurationMatchesProofOfConceptBudget() {
        XCTAssertEqual(M1Configuration.request.latitude, 10.759157)
        XCTAssertEqual(M1Configuration.request.longitude, 106.675859)
        XCTAssertEqual(M1Configuration.request.zoom, 17)
        XCTAssertEqual(M1Configuration.request.width, 212)
        XCTAssertEqual(M1Configuration.request.height, 360)
        XCTAssertEqual(M1Configuration.maximumProviderCalls, 1)
    }

    func testStartRequiresRPKBeforeLoadingServiceKeyOrCallingProvider() async {
        let keys = M1KeyStore(serviceKey: "secret-service-key")
        let provider = M1Provider(result: .success(try! makeAsset()))
        let model = makeModel(keys: keys, provider: provider)
        keys.resetLoads()

        await model.startM1()

        XCTAssertEqual(model.m1State, .failed(code: "RPK_NOT_READY"))
        XCTAssertEqual(keys.loads, [])
        let fetchCount = await provider.fetchCount
        XCTAssertEqual(fetchCount, 0)
    }

    func testStartRequiresSavedServiceKeyAndNeverLoadsTileMapKey() async {
        let keys = M1KeyStore(serviceKey: nil)
        let provider = M1Provider(result: .success(try! makeAsset()))
        let model = makeModel(keys: keys, provider: provider)
        model.consume(.connected)
        keys.resetLoads()

        await model.startM1()

        XCTAssertEqual(model.m1State, .failed(code: "SERVICE_KEY_MISSING"))
        XCTAssertEqual(keys.loads, [.service])
        let fetchCount = await provider.fetchCount
        XCTAssertEqual(fetchCount, 0)
    }

    func testOnePressFetchesOnceAndSendsEveryStepSequentiallyThroughACKs() async throws {
        let asset = try makeAsset(byteCount: 700)
        let plan = try MapAssetTransferPlan.make(asset: asset)
        let provider = M1Provider(result: .success(asset))
        let sender = M1AcknowledgingSender()
        let model = readyModel(provider: provider, sender: sender)

        let start = Task { await model.startM1() }
        await waitUntil { await sender.startedCount == 1 }
        XCTAssertEqual(model.m1State, .transferring(completed: 0, total: plan.count))
        var maximumInFlight = await sender.maximumInFlight
        XCTAssertEqual(maximumInFlight, 1)

        for completed in 1...plan.count {
            await sender.acknowledgeNext()
            if completed < plan.count {
                await waitUntil { await sender.startedCount == completed + 1 }
                XCTAssertEqual(model.m1State, .transferring(completed: completed, total: plan.count))
                maximumInFlight = await sender.maximumInFlight
                XCTAssertEqual(maximumInFlight, 1)
            }
        }
        await start.value

        let fetchCount = await provider.fetchCount
        let requests = await provider.requests
        let sentSteps = await sender.steps
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(requests, [M1Configuration.request])
        XCTAssertEqual(sentSteps, plan)
        XCTAssertEqual(model.m1State, .waitingForBand(
            assetID: asset.id,
            hashPrefix: String(asset.sha256.prefix(8))
        ))
    }

    func testBandWriteFailureBeforeChunkACKStopsRemainingTransferSteps() async throws {
        let asset = try makeAsset(byteCount: 700)
        let sender = M1AcknowledgingSender()
        let model = readyModel(provider: M1Provider(result: .success(asset)), sender: sender)
        let start = Task { await model.startM1() }
        await waitUntil { await sender.startedCount == 1 }
        await sender.acknowledgeNext()
        await waitUntil { await sender.startedCount == 2 }

        model.consume(.received(resultEnvelope(
            asset: asset.id,
            status: "error",
            bytes: 0,
            prefix: String(asset.sha256.prefix(8)),
            code: "ASSET_WRITE_FAILED"
        )))
        XCTAssertEqual(model.m1State, .failed(code: "ASSET_WRITE_FAILED"))
        var sentSteps = await sender.steps
        XCTAssertEqual(sentSteps.count, 2)
        await sender.acknowledgeNext()
        await waitUntil {
            if model.m1State == .failed(code: "ASSET_WRITE_FAILED") { return true }
            return await sender.startedCount > 2
        }

        XCTAssertEqual(model.m1State, .failed(code: "ASSET_WRITE_FAILED"))
        sentSteps = await sender.steps
        XCTAssertEqual(sentSteps.count, 2)
        XCTAssertEqual(sentSteps.map(\.topic), ["map.asset.begin", "map.asset.chunk"])
        await finishBlockedStart(start, sender: sender)
    }

    func testMatchingBoundedBandFailuresAreAcceptedDuringTransfer() async throws {
        for (code, prefix) in [
            ("ASSET_BEGIN_INVALID", ""),
            ("ASSET_OFFSET_INVALID", String(try makeAsset().sha256.prefix(8))),
        ] {
            let asset = try makeAsset()
            let sender = M1AcknowledgingSender()
            let model = readyModel(provider: M1Provider(result: .success(asset)), sender: sender)
            let start = Task { await model.startM1() }
            await waitUntil { await sender.startedCount == 1 }

            model.consume(.received(resultEnvelope(
                asset: asset.id,
                status: "error",
                bytes: 0,
                prefix: prefix,
                code: code
            )))
            XCTAssertEqual(model.m1State, .failed(code: code))
            await sender.acknowledgeNext()
            await waitUntil {
                if model.m1State == .failed(code: code) { return true }
                return await sender.startedCount > 1
            }

            XCTAssertEqual(model.m1State, .failed(code: code))
            let sentCount = await sender.startedCount
            XCTAssertEqual(sentCount, 1)
            await finishBlockedStart(start, sender: sender)
        }
    }

    func testMatchingOKDuringTransferFailsInvalidAndNeverDisplaysOrSendsNextStep() async throws {
        let asset = try makeAsset()
        let sender = M1AcknowledgingSender()
        let model = readyModel(provider: M1Provider(result: .success(asset)), sender: sender)
        let start = Task { await model.startM1() }
        await waitUntil { await sender.startedCount == 1 }

        model.consume(.received(resultEnvelope(
            asset: asset.id,
            status: "ok",
            bytes: asset.byteCount,
            prefix: String(asset.sha256.prefix(8))
        )))
        XCTAssertEqual(model.m1State, .failed(code: "ASSET_RESULT_INVALID"))
        await sender.acknowledgeNext()
        await waitUntil {
            if model.m1State == .failed(code: "ASSET_RESULT_INVALID") { return true }
            return await sender.startedCount > 1
        }

        XCTAssertEqual(model.m1State, .failed(code: "ASSET_RESULT_INVALID"))
        let sentCount = await sender.startedCount
        XCTAssertEqual(sentCount, 1)
        await finishBlockedStart(start, sender: sender)
    }

    func testCancellationBeforeSuccessfulACKStopsRemainingTransferSteps() async throws {
        let sender = M1AcknowledgingSender()
        let model = readyModel(
            provider: M1Provider(result: .success(try makeAsset())),
            sender: sender
        )
        let start = Task { await model.startM1() }
        await waitUntil { await sender.startedCount == 1 }

        start.cancel()
        await sender.acknowledgeNext()
        await waitUntil {
            if model.m1State == .failed(code: "TRANSFER_CANCELLED") { return true }
            return await sender.startedCount > 1
        }
        await start.value

        XCTAssertEqual(model.m1State, .failed(code: "TRANSFER_CANCELLED"))
        let sentCount = await sender.startedCount
        XCTAssertEqual(sentCount, 1)
    }

    func testMalformedAndMismatchedResultsRemainIgnoredDuringTransfer() async throws {
        let asset = try makeAsset()
        let sender = M1AcknowledgingSender()
        let model = readyModel(provider: M1Provider(result: .success(asset)), sender: sender)
        let start = Task { await model.startM1() }
        await waitUntil { await sender.startedCount == 1 }
        let transferring = model.m1State

        model.consume(.received(resultEnvelope(
            asset: "m1-0000000000000000",
            status: "error",
            bytes: 0,
            prefix: "",
            code: "ASSET_BEGIN_INVALID"
        )))
        model.consume(.received(.message(
            id: "b-malformed-transfer",
            source: .band,
            topic: "map.asset.result",
            body: [
                "asset": .string(asset.id),
                "status": .string("error"),
                "bytes": .string("0"),
                "sha256Prefix": .string(""),
                "code": .string("ASSET_BEGIN_INVALID"),
            ]
        )))

        XCTAssertEqual(model.m1State, transferring)
        let sentCount = await sender.startedCount
        XCTAssertEqual(sentCount, 1)
        await finishBlockedStart(start, sender: sender)
    }

    func testBusyPressDoesNotFetchAgainAndTerminalPressIsOnlyRetry() async throws {
        let asset = try makeAsset()
        let provider = M1Provider(result: .success(asset))
        let sender = M1AcknowledgingSender()
        let model = readyModel(provider: provider, sender: sender)

        let first = Task { await model.startM1() }
        await waitUntil { await sender.startedCount == 1 }
        await model.startM1()
        var fetchCount = await provider.fetchCount
        XCTAssertEqual(fetchCount, 1)

        await sender.failNext(M1TransferTestError.failed)
        await first.value
        XCTAssertEqual(model.m1State, .failed(code: "TRANSFER_FAILED"))

        let second = Task { await model.startM1() }
        await waitUntil { await provider.fetchCount == 2 }
        second.cancel()
        await sender.failNext(CancellationError())
        await second.value
        fetchCount = await provider.fetchCount
        XCTAssertEqual(fetchCount, 2)
    }

    func testProviderAndAssetErrorsMapToStableCodesWithoutLeakingDescriptions() async {
        let cases: [(any Swift.Error, String)] = [
            (VietmapStaticMapError.rateLimited, "PROVIDER_RATE_LIMITED"),
            (VietmapStaticMapError.httpStatus(418), "PROVIDER_HTTP"),
            (VietmapStaticMapError.wrongContentType, "PROVIDER_MIME"),
            (VietmapStaticMapError.invalidRequest, "PROVIDER_REQUEST"),
            (M1ProviderTestError.message("secret-service-key"), "PROVIDER_REQUEST"),
            (MapAsset.Error.invalidPNG, "ASSET_INVALID"),
        ]

        for (error, code) in cases {
            let provider = M1Provider(result: .failure(error))
            let model = readyModel(provider: provider)
            await model.startM1()
            XCTAssertEqual(model.m1State, .failed(code: code))
            XCTAssertFalse(String(describing: model.m1State).contains("secret-service-key"))
        }
    }

    func testTransferErrorsMapToStableCodes() async throws {
        let cases: [(any Swift.Error, String)] = [
            (InterconnectDeliveryError.timeout("private-id"), "TRANSFER_TIMEOUT"),
            (InterconnectDeliveryError.disconnected, "TRANSFER_DISCONNECTED"),
            (BandSessionError.notConnected, "TRANSFER_DISCONNECTED"),
            (CancellationError(), "TRANSFER_CANCELLED"),
            (InterconnectDeliveryError.identifierCollision("private-id"), "TRANSFER_FAILED"),
            (M1TransferTestError.failed, "TRANSFER_FAILED"),
        ]

        for (error, code) in cases {
            let sender = M1ImmediateSender(error: error)
            let model = readyModel(provider: M1Provider(result: .success(try makeAsset())), sender: sender)
            await model.startM1()
            XCTAssertEqual(model.m1State, .failed(code: code))
            XCTAssertFalse(String(describing: model.m1State).contains("private-id"))
        }
    }

    func testMatchingBandResultDisplaysOnlyAfterExactRenderConfirmation() async throws {
        let asset = try makeAsset()
        let model = readyModel(provider: M1Provider(result: .success(asset)), sender: M1ImmediateSender())
        await model.startM1()
        XCTAssertEqual(model.m1State, .waitingForBand(assetID: asset.id, hashPrefix: String(asset.sha256.prefix(8))))

        model.consume(.received(resultEnvelope(
            asset: asset.id,
            status: "ok",
            bytes: asset.byteCount,
            prefix: String(asset.sha256.prefix(8))
        )))

        XCTAssertEqual(model.m1State, .displayed(assetID: asset.id, hashPrefix: String(asset.sha256.prefix(8))))
    }

    func testMatchingBandErrorUsesOnlyBoundedAssetCode() async throws {
        let asset = try makeAsset()
        let model = readyModel(provider: M1Provider(result: .success(asset)), sender: M1ImmediateSender())
        await model.startM1()

        model.consume(.received(resultEnvelope(
            asset: asset.id,
            status: "error",
            bytes: asset.byteCount,
            prefix: String(asset.sha256.prefix(8)),
            code: "ASSET_RENDER"
        )))
        XCTAssertEqual(model.m1State, .failed(code: "ASSET_RENDER"))

        await model.startM1()
        model.consume(.received(resultEnvelope(
            asset: asset.id,
            status: "error",
            bytes: asset.byteCount,
            prefix: String(asset.sha256.prefix(8)),
            code: "raw key secret-service-key"
        )))
        XCTAssertEqual(model.m1State, .failed(code: "ASSET_RESULT_INVALID"))
    }

    func testMismatchedMalformedAndStaleResultsAreIgnored() async throws {
        let asset = try makeAsset()
        let model = readyModel(provider: M1Provider(result: .success(asset)), sender: M1ImmediateSender())
        await model.startM1()
        let waiting = model.m1State

        model.consume(.received(resultEnvelope(
            asset: "m1-0000000000000000",
            status: "ok",
            bytes: asset.byteCount,
            prefix: String(asset.sha256.prefix(8))
        )))
        XCTAssertEqual(model.m1State, waiting)

        model.consume(.received(.message(
            id: "b-malformed",
            source: .band,
            topic: "map.asset.result",
            body: [
                "asset": .string(asset.id),
                "status": .string("ok"),
                "bytes": .string(String(asset.byteCount)),
                "sha256Prefix": .string(String(asset.sha256.prefix(8))),
            ]
        )))
        XCTAssertEqual(model.m1State, waiting)

        model.consume(.received(resultEnvelope(
            asset: asset.id,
            status: "ok",
            bytes: asset.byteCount,
            prefix: "00000000"
        )))
        XCTAssertEqual(model.m1State, .failed(code: "ASSET_RESULT_INVALID"))

        model.consume(.received(resultEnvelope(
            asset: asset.id,
            status: "ok",
            bytes: asset.byteCount,
            prefix: String(asset.sha256.prefix(8))
        )))
        XCTAssertEqual(model.m1State, .failed(code: "ASSET_RESULT_INVALID"))
    }

    func testInitAndConnectedEventNeverStartM1Automatically() async {
        let provider = M1Provider(result: .success(try! makeAsset()))
        let model = makeModel(keys: M1KeyStore(serviceKey: "secret-service-key"), provider: provider)
        var fetchCount = await provider.fetchCount
        XCTAssertEqual(fetchCount, 0)

        model.consume(.connected)
        await Task.yield()

        XCTAssertEqual(model.m1State, .idle)
        fetchCount = await provider.fetchCount
        XCTAssertEqual(fetchCount, 0)
    }

    func testExplicitDisconnectTerminatesWaitingM1WithoutAnotherProviderCall() async throws {
        let provider = M1Provider(result: .success(try makeAsset()))
        let model = readyModel(provider: provider, sender: M1ImmediateSender())
        await model.startM1()

        await model.disconnect()

        XCTAssertEqual(model.m1State, .failed(code: "TRANSFER_DISCONNECTED"))
        let fetchCount = await provider.fetchCount
        XCTAssertEqual(fetchCount, 1)
    }

    private func readyModel(
        provider: M1Provider,
        sender: any M1SessionSending = M1ImmediateSender()
    ) -> AppModel {
        let model = makeModel(
            keys: M1KeyStore(serviceKey: "secret-service-key"),
            provider: provider,
            sender: sender
        )
        model.consume(.connected)
        return model
    }

    private func makeModel(
        keys: M1KeyStore,
        provider: M1Provider,
        sender: any M1SessionSending = M1ImmediateSender()
    ) -> AppModel {
        let central = M1Central()
        let trustStore = M1TrustStore()
        let cipher = M1Cipher()
        let session = BandSession(
            central: central,
            authenticator: BandAuthenticator(cipher: cipher),
            cipher: cipher,
            trustedRPKStore: trustStore
        )
        return AppModel(
            keyStore: M1AuthKeyStore(),
            vietmapKeyStore: keys,
            bandStore: M1RememberedBandStore(),
            trustedRPKStore: trustStore,
            central: central,
            session: session,
            staticMapProvider: provider,
            m1Session: sender
        )
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

    private func finishBlockedStart(
        _ task: Task<Void, Never>,
        sender: M1AcknowledgingSender
    ) async {
        task.cancel()
        if await sender.waitingCount > 0 {
            await sender.failNext(CancellationError())
        }
        await task.value
    }
}

private final class M1KeyStore: VietmapKeyStoreProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private let serviceKey: String?
    private(set) var loads: [VietmapKeyKind] = []

    init(serviceKey: String?) { self.serviceKey = serviceKey }

    func load(_ kind: VietmapKeyKind) throws -> String? {
        lock.lock()
        loads.append(kind)
        lock.unlock()
        return kind == .service ? serviceKey : nil
    }

    func save(_ value: String, kind: VietmapKeyKind) throws {}
    func delete(_ kind: VietmapKeyKind) throws {}

    func resetLoads() {
        lock.lock()
        loads = []
        lock.unlock()
    }
}

private actor M1Provider: StaticMapProviding {
    private let result: Result<MapAsset, any Swift.Error>
    private(set) var requests: [StaticMapRequest] = []
    var fetchCount: Int { requests.count }

    init(result: Result<MapAsset, any Swift.Error>) { self.result = result }

    func fetch(_ request: StaticMapRequest, serviceKey: String) async throws -> MapAsset {
        requests.append(request)
        return try result.get()
    }
}

private actor M1AcknowledgingSender: M1SessionSending {
    private(set) var steps: [MapTransferStep] = []
    private(set) var inFlight = 0
    private(set) var maximumInFlight = 0
    private var waiters: [CheckedContinuation<Void, any Swift.Error>] = []
    var startedCount: Int { steps.count }
    var waitingCount: Int { waiters.count }

    func sendAwaitingAcknowledgement(topic: String, body: [String: JSONValue]) async throws {
        steps.append(MapTransferStep(topic: topic, body: body))
        inFlight += 1
        maximumInFlight = max(maximumInFlight, inFlight)
        defer { inFlight -= 1 }
        try await withCheckedThrowingContinuation { waiters.append($0) }
    }

    func acknowledgeNext() { waiters.removeFirst().resume() }
    func failNext(_ error: any Swift.Error) { waiters.removeFirst().resume(throwing: error) }
}

private actor M1ImmediateSender: M1SessionSending {
    private let error: (any Swift.Error)?
    init(error: (any Swift.Error)? = nil) { self.error = error }

    func sendAwaitingAcknowledgement(topic: String, body: [String: JSONValue]) async throws {
        if let error { throw error }
    }
}

private enum M1ProviderTestError: Swift.Error { case message(String) }
private enum M1TransferTestError: Swift.Error { case failed }

private struct M1AuthKeyStore: AuthKeyStoreProtocol, Sendable {
    func load() throws -> AuthKey? { nil }
    func save(_ key: AuthKey) throws {}
    func delete() throws {}
}

private final class M1RememberedBandStore: RememberedBandStoreProtocol, @unchecked Sendable {
    func load() -> RememberedBand? { nil }
    func save(_ band: RememberedBand) {}
    func forget() {}
}

private actor M1TrustStore: TrustedRPKStore {
    func trustedRPKFingerprint() async throws -> Data? { nil }
    func saveTrustedRPKFingerprint(_ fingerprint: Data) async throws {}
    func resetTrustedRPKFingerprint() async throws {}
}

private struct M1Cipher: AESBlockCipher {
    func encrypt(block: Data, key: Data) throws -> Data { block }
}

private actor M1Central: BandCentralProtocol {
    func scan() async -> AsyncThrowingStream<[BandCandidate], any Swift.Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func stopScan() async {}
    func connect(id: UUID) async throws -> any BandLink { throw M1TransferTestError.failed }
}

private func makeAsset(byteCount: Int = 64) throws -> MapAsset {
    var bytes: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82]
    bytes.append(contentsOf: bigEndianBytes(212))
    bytes.append(contentsOf: bigEndianBytes(360))
    bytes.append(contentsOf: [8, 6, 0, 0, 0])
    if bytes.count < byteCount {
        bytes.append(contentsOf: (bytes.count..<byteCount).map { UInt8(truncatingIfNeeded: $0) })
    }
    return try MapAsset.png(data: Data(bytes), expectedWidth: 212, expectedHeight: 360)
}

private func bigEndianBytes(_ value: Int) -> [UInt8] {
    let value = UInt32(value)
    return [UInt8(value >> 24), UInt8(value >> 16), UInt8(value >> 8), UInt8(value)]
}

private func resultEnvelope(
    asset: String,
    status: String,
    bytes: Int,
    prefix: String,
    code: String? = nil
) -> ApplicationEnvelope {
    var body: [String: JSONValue] = [
        "asset": .string(asset),
        "status": .string(status),
        "bytes": .number(Double(bytes)),
        "sha256Prefix": .string(prefix),
    ]
    if let code { body["code"] = .string(code) }
    return .message(id: "b-result", source: .band, topic: "map.asset.result", body: body)
}
