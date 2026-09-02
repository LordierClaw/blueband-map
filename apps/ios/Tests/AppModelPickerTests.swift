import Foundation
import CoreGraphics
import CoreLocation
import XCTest
import BlueBandCore
import BlueBandCrypto
import BlueBandMapCore
import BlueBandProtocol
@testable import BlueBandMap

@MainActor
final class AppModelPickerTests: XCTestCase {
    func testMovingGPSIsNotBlockedByRenderingAndFinalFixPublishesAfterCooldown() async throws {
        let manager = TestLocationManager()
        let location = ForegroundLocationClient(manager: manager, makeBackgroundActivity: { nil }, servicesEnabled: { true })
        let sender = WindowedRouteCardSession()
        var requests: [VietmapSnapshotRequest] = []
        let renderedTwice = expectation(description: "newest GPS snapshot after cooldown")
        let model = makeModel(
            central: PickerCentral(), authMode: .missing, location: location, navigationConfigured: true,
            routeTransport: ReplayRouteTransport(), sender: sender,
            render: { request in
                requests.append(request)
                if requests.count == 1 { try await Task.sleep(for: .milliseconds(200)) }
                if requests.count == 2 { renderedTwice.fulfill() }
                let context = CGContext(data: nil, width: 424, height: 1040, bitsPerComponent: 8,
                                        bytesPerRow: 424 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                let configuration = try VietmapSnapshotConfiguration.make(request)
                return VietmapSnapshotOutput(image: context.makeImage()!, retainedFillLayers: 0,
                    retainedLineLayers: 0, retainedSymbolLayers: 0, zoom: configuration.zoom,
                    styleLoadMilliseconds: 0, snapshotMilliseconds: 200, cacheState: "test",
                    configuration: configuration)
            }
        )
        await sender.setReceiver { [weak model] envelope in model?.consume(.received(envelope)) }
        model.destinationLatitudeInput = "0.002"
        model.destinationLongitudeInput = "0.001"
        model.consume(.connected)
        model.startNavigation()
        await waitUntil { manager.updating }
        func fix(_ latitude: Double) -> CLLocation {
            CLLocation(coordinate: .init(latitude: latitude, longitude: 0), altitude: 0,
                       horizontalAccuracy: 5, verticalAccuracy: 5, course: 0, speed: 3, timestamp: Date())
        }
        location.locationManager(manager, didUpdateLocations: [fix(0)])
        await waitUntil { requests.count == 1 }
        location.locationManager(manager, didUpdateLocations: [fix(0.0001), fix(0.0002)])
        await waitUntil { model.navigationDebugEntries.contains { $0.stage == "guidance.fix" } }
        XCTAssertEqual(requests.count, 1, "guidance must consume movement before slow render finishes")
        XCTAssertEqual(location.acceptedFixCount, 3)
        await fulfillment(of: [renderedTwice], timeout: 3)
        await waitUntil { model.navigationDebugEntries.filter { $0.stage == "band.displayed" }.count == 2 }
        XCTAssertNotNil(model.routePreviewPNG)
        XCTAssertNotNil(model.lastMapFixAgeMilliseconds)
        XCTAssertLessThan(model.lastMapFixAgeMilliseconds ?? .max, 5_000)
        XCTAssertEqual(requests.last?.matchedPosition.latitude ?? -1, 0.0002, accuracy: 0.00001)
        for request in requests {
            let config = try VietmapSnapshotConfiguration.make(request)
            let marker = config.point(for: request.matchedPosition)
            XCTAssertEqual(marker.x, 106, accuracy: 0.5)
            XCTAssertEqual(marker.y, 374, accuracy: 0.5)
        }
        model.stopNavigation()
    }

    func testCancelledNavigationEpilogueCannotStopRestartedGPS() async {
        let central = PickerCentral()
        let manager = TestLocationManager()
        let location = ForegroundLocationClient(manager: manager, makeBackgroundActivity: { nil }, servicesEnabled: { true })
        let model = makeModel(central: central, authMode: .missing, location: location, navigationConfigured: true)
        model.destinationLatitudeInput = "21.1"
        model.destinationLongitudeInput = "106.1"
        model.consume(.connected)
        model.startNavigation()
        await waitUntil { manager.updating }
        model.stopNavigation()
        model.startNavigation()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertTrue(manager.updating, "old navigation defer must not stop the new session")
        XCTAssertTrue(manager.backgroundEnabled)
        XCTAssertEqual(model.navigationState, .waitingForGPS)
        model.stopNavigation()
    }

    func testNavigationMarkerIsFixedAtTheLowerCenter() {
        XCTAssertEqual(AppModel.fixedNavigationMarker, ScreenPoint(x: 106, y: 374))
    }

    func testHeadingBucketRoundsCompassCourseIntoEightResources() {
        XCTAssertEqual(AppModel.headingBucket(-1), 0)
        XCTAssertEqual(AppModel.headingBucket(22), 0)
        XCTAssertEqual(AppModel.headingBucket(23), 1)
        XCTAssertEqual(AppModel.headingBucket(180), 4)
        XCTAssertEqual(AppModel.headingBucket(359), 0)
    }

    func testRouteHeadingRequiresReliableMovement() {
        XCTAssertNil(AppModel.initialRouteHeading(courseDegrees: 214, speedMetersPerSecond: -1))
        XCTAssertNil(AppModel.initialRouteHeading(courseDegrees: 214, speedMetersPerSecond: 0))
        XCTAssertNil(AppModel.initialRouteHeading(courseDegrees: -1, speedMetersPerSecond: 5))
        XCTAssertNil(AppModel.initialRouteHeading(courseDegrees: 361, speedMetersPerSecond: 5))
        XCTAssertEqual(AppModel.initialRouteHeading(courseDegrees: 214.4, speedMetersPerSecond: 1), 214)
        XCTAssertEqual(AppModel.routeHeading(courseDegrees: 214.4), 214)
    }

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
        authMode: PickerAuthKeyStore.Mode,
        location: ForegroundLocationClient? = nil,
        navigationConfigured: Bool = false,
        routeTransport: (any MapHTTPTransport)? = nil,
        sender: (any RouteCardSessionSending)? = nil,
        render: (@MainActor (VietmapSnapshotRequest) async throws -> VietmapSnapshotOutput)? = nil
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
            vietmapKeyStore: PickerVietmapKeyStore(configured: navigationConfigured),
            bandStore: PickerRememberedBandStore(),
            trustedRPKStore: trustStore,
            central: central,
            session: session,
            routeClient: VietmapRouteClient(transport: routeTransport ?? transport),
            snapshotRenderer: VietmapSnapshotRenderer(),
            locationClient: location ?? ForegroundLocationClient(),
            routeCardSession: sender,
            snapshotRender: render,
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
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
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
    var configured = false
    func load(_ kind: VietmapKeyKind) throws -> String? { configured ? "test-provider-key" : nil }
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

private struct ReplayRouteTransport: MapHTTPTransport {
    func execute(_ request: MapHTTPRequest) async throws -> MapHTTPResponse {
        MapHTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"], body: Data(#"{"code":"OK","paths":[{"distance":270,"points_encoded":true,"points":"??gE?gEgE","instructions":[{"distance":111,"heading":0,"sign":0,"interval":[0,1],"street_name":"Đường A"},{"distance":157,"heading":45,"sign":2,"interval":[1,2],"street_name":"Đường B"},{"distance":0,"heading":0,"sign":4,"interval":[2,2],"street_name":""}]}]}"#.utf8))
    }
}
