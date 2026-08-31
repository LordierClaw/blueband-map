import Foundation
import XCTest
import BlueBandCore
import BlueBandCrypto
import BlueBandMapCore
import BlueBandProtocol
@testable import BlueBandMap

@MainActor
final class AppModelPickerTests: XCTestCase {
    func testSelectingWithoutAuthKeyKeepsOwnedScanActive() async {
        let central = PickerCentral()
        let model = makeModel(central: central, authMode: .missing)
        let scanTask = Task { await model.scan() }
        await waitUntil { await central.scanCount() == 1 }

        await model.connect(to: candidate)

        XCTAssertEqual(model.sessionState, .scanning)
        XCTAssertEqual(model.errorMessage, "Hãy lưu AuthKey trước khi kết nối.")
        await finishAndAwait(scanTask, central: central, scanIndex: 0)
    }

    func testSelectingWithUnreadableAuthKeyKeepsOwnedScanActive() async {
        let central = PickerCentral()
        let model = makeModel(central: central, authMode: .invalid)
        let scanTask = Task { await model.scan() }
        await waitUntil { await central.scanCount() == 1 }

        await model.connect(to: candidate)

        XCTAssertEqual(model.sessionState, .scanning)
        XCTAssertEqual(model.errorMessage, "Không đọc được AuthKey trong Keychain.")
        await finishAndAwait(scanTask, central: central, scanIndex: 0)
    }

    func testStaleScanEpilogueCannotResetExplicitRescan() async {
        let central = PickerCentral()
        let model = makeModel(central: central, authMode: .missing)
        let firstScan = Task { await model.scan() }
        await waitUntil { await central.scanCount() == 1 }

        await model.stopScan()
        let secondScan = Task { await model.scan() }
        await waitUntil {
            let count = await central.scanCount()
            return count == 2 && model.sessionState == .scanning
        }

        await central.finishScan(at: 0)
        await firstScan.value

        XCTAssertEqual(model.sessionState, .scanning)
        await finishAndAwait(secondScan, central: central, scanIndex: 1)
    }

    func testCancellingScanConsumerStopsItsOwnedCentralScan() async {
        let central = PickerCentral()
        let model = makeModel(central: central, authMode: .missing)
        let scanTask = Task { await model.scan() }
        await waitUntil { await central.scanCount() == 1 }

        scanTask.cancel()

        await waitUntil { await central.stopCount() == 1 }
        await scanTask.value
        XCTAssertEqual(model.sessionState, .idle)
    }

    private var candidate: BandCandidate {
        BandCandidate(
            id: UUID(uuidString: "70000000-0000-0000-0000-000000000000")!,
            name: "Xiaomi Smart Band 10",
            rssi: -42
        )
    }

    private func makeModel(
        central: PickerCentral,
        authMode: PickerAuthKeyStore.Mode
    ) -> AppModel {
        let cipher = PickerCipher()
        let trustStore = PickerTrustStore()
        let session = BandSession(
            central: central,
            authenticator: BandAuthenticator(cipher: cipher),
            cipher: cipher,
            trustedRPKStore: trustStore
        )
        let transport = URLSessionHTTPTransport()
        return AppModel(
            keyStore: PickerAuthKeyStore(mode: authMode),
            vietmapKeyStore: PickerVietmapKeyStore(),
            bandStore: PickerRememberedBandStore(),
            trustedRPKStore: trustStore,
            central: central,
            session: session,
            routeClient: VietmapRouteClient(transport: transport),
            assetFactory: RouteCardAssetFactory(
                styleClient: VietmapStyleClient(transport: transport),
                tileTransport: transport
            ),
            locationClient: ForegroundLocationClient(),
            scanDuration: .seconds(3_600)
        )
    }

    private func finishAndAwait(
        _ task: Task<Void, Never>,
        central: PickerCentral,
        scanIndex: Int
    ) async {
        await central.finishScan(at: scanIndex)
        await task.value
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<200 {
            if await condition() { return }
            await Task.yield()
        }
        XCTFail("Condition was not met", file: file, line: line)
    }
}

private struct PickerAuthKeyStore: AuthKeyStoreProtocol, Sendable {
    enum Mode: Sendable { case missing, invalid }
    enum StoreError: Swift.Error { case invalidStoredValue }

    let mode: Mode

    func load() throws -> AuthKey? {
        switch mode {
        case .missing: return nil
        case .invalid: throw StoreError.invalidStoredValue
        }
    }

    func save(_ key: AuthKey) throws {}
    func delete() throws {}
}

private struct PickerVietmapKeyStore: VietmapKeyStoreProtocol, Sendable {
    func load(_ kind: VietmapKeyKind) throws -> String? { nil }
    func save(_ value: String, kind: VietmapKeyKind) throws {}
    func delete(_ kind: VietmapKeyKind) throws {}
}

private final class PickerRememberedBandStore: RememberedBandStoreProtocol, @unchecked Sendable {
    func load() -> RememberedBand? { nil }
    func save(_ band: RememberedBand) {}
    func forget() {}
}

private actor PickerTrustStore: TrustedRPKStore {
    func trustedRPKFingerprint() async throws -> Data? { nil }
    func saveTrustedRPKFingerprint(_ fingerprint: Data) async throws {}
    func resetTrustedRPKFingerprint() async throws {}
}

private struct PickerCipher: AESBlockCipher {
    func encrypt(block: Data, key: Data) throws -> Data { block }
}

private actor PickerCentral: BandCentralProtocol {
    private var continuations: [AsyncThrowingStream<[BandCandidate], Swift.Error>.Continuation] = []
    private var stops = 0

    func scan() async -> AsyncThrowingStream<[BandCandidate], Swift.Error> {
        var continuation: AsyncThrowingStream<[BandCandidate], Swift.Error>.Continuation!
        let stream = AsyncThrowingStream<[BandCandidate], Swift.Error> { continuation = $0 }
        continuations.append(continuation)
        return stream
    }

    func stopScan() async { stops += 1 }

    func connect(id: UUID) async throws -> any BandLink {
        throw PickerCentralError.unexpectedConnect
    }

    func finishScan(at index: Int) {
        continuations[index].finish()
    }

    func scanCount() -> Int { continuations.count }
    func stopCount() -> Int { stops }
}

private enum PickerCentralError: Swift.Error {
    case unexpectedConnect
}
