# M1 Persistent Configuration and Static Map POC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the configure-once iOS test workflow and prove one real Vietmap street PNG through fetch, acknowledged application-envelope chunks, Band file storage, SHA-256 verification, and Vela image rendering.

**Architecture:** Add a portable `BlueBandMapCore` target for Vietmap Static Map request/response validation, PNG inspection, asset hashing, and 512-byte-safe transfer planning. Keep Keychain, URLSession, SwiftUI, and CoreBluetooth selection in the iOS application boundary. Extend the existing acknowledged Application Envelope v1 session with an awaitable delivery API; preserve all Xiaomi SPP/auth/ThirdPartyApp bytes. The Band remains one Vela page and uses `system.file` plus `system.crypto` to write ordered chunks, verify the completed file, then atomically expose the image.

**Tech Stack:** Swift 6 package in Swift 5 language mode, Foundation/FoundationNetworking, swift-crypto, XCTest, SwiftUI, Security/Keychain, CoreBluetooth, Xiaomi Vela Quick App JavaScript, `system.interconnect`, `system.file`, `system.crypto`, Node test runner, Docker-backed `make` commands.

---

## Scope and file map

This plan implements only persistent test configuration, the compact Band picker, and M1. It does not implement multi-tile M2, pan, rotation, route data, navigation SDK, background modes, Share Extensions, retry loops, or provider caching.

### New portable product-domain files

- `packages/BlueBandKit/Sources/BlueBandMapCore/HTTPTransport.swift`: small provider-neutral HTTP request/response boundary.
- `packages/BlueBandKit/Sources/BlueBandMapCore/MapAsset.swift`: validated raster asset and SHA-256 identity.
- `packages/BlueBandKit/Sources/BlueBandMapCore/PNGInspector.swift`: PNG signature and IHDR dimension validation.
- `packages/BlueBandKit/Sources/BlueBandMapCore/VietmapStaticMapClient.swift`: deterministic multipart request and bounded PNG response contract.
- `packages/BlueBandKit/Sources/BlueBandMapCore/MapAssetTransferPlan.swift`: `map.asset.*` bodies and dynamic envelope-safe chunk sizing.
- `packages/BlueBandKit/Tests/BlueBandMapCoreTests/*.swift`: Linux-capable behavioral tests for those files.

### New iOS boundary files

- `apps/ios/Adapters/Keychain/KeychainVietmapKeyStore.swift`: independent TileMap and Service key persistence.
- `apps/ios/Adapters/Vietmap/URLSessionHTTPTransport.swift`: live HTTPS adapter with no request logging.
- `apps/ios/App/ConfigView.swift`: masked persistent configuration UI.
- `apps/ios/App/BandPickerView.swift`: compact scan/select dialog.
- `apps/ios/App/BandCandidateOrdering.swift`: pure remembered-first/RSSI ordering policy.
- `apps/ios/App/M1State.swift`: explicit POC state and safe error labels.

### Modified boundaries

- `packages/BlueBandKit/Package.swift`: expose and test `BlueBandMapCore`.
- `packages/BlueBandKit/Sources/BlueBandCore/InterconnectSession.swift`: await one existing application ACK without wire changes.
- `packages/BlueBandKit/Sources/BlueBandCore/BandSession.swift`: forward awaitable message delivery.
- `apps/ios/Adapters/Keychain/UserDefaultsRememberedBandStore.swift`: persist last successful connection date.
- `apps/ios/App/AppModel.swift`: configuration actions, picker ordering, M1 orchestration and semantic result handling.
- `apps/ios/App/BlueBandMapApp.swift`: compose the new stores and live provider transport.
- `apps/ios/App/ContentView.swift`: present Config and Band picker sheets and an M1 test section.
- `apps/ios/project.yml`: link `BlueBandMapCore`.
- `apps/band/src/manifest.json`: declare file and crypto features and increment RPK version.
- `apps/band/src/pages/index/index.ux`: ordered asset assembler, SHA-256 gate and image UI.
- `apps/band/test/*.mjs`: behavioral page tests and updated package contract.
- `docs/testing/results/2026-08-29-m1-test-packet.md`: exact owner-run test packet, not a claimed result.

## Task 1: Add portable BlueBandMapCore target

**Files:**
- Modify: `packages/BlueBandKit/Package.swift`
- Create: `packages/BlueBandKit/Sources/BlueBandMapCore/HTTPTransport.swift`
- Create: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/HTTPTransportTests.swift`

- [ ] **Step 1: Write the failing package-surface test**

Create `HTTPTransportTests.swift`:

```swift
import Foundation
import XCTest
@testable import BlueBandMapCore

final class HTTPTransportTests: XCTestCase {
    func testRequestAndResponsePreserveOnlyExplicitHTTPFields() async throws {
        let request = MapHTTPRequest(
            method: "POST",
            url: try XCTUnwrap(URL(string: "https://maps.vietmap.vn/api/maps/statics/tm")),
            headers: ["Content-Type": "multipart/form-data; boundary=blueband"],
            body: Data("body".utf8)
        )
        let transport = RecordingHTTPTransport(
            response: MapHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data([1, 2]))
        )

        let response = try await transport.execute(request)

        XCTAssertEqual(await transport.lastRequest(), request)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.header(named: "Content-Type"), "image/png")
    }
}

private actor RecordingHTTPTransport: MapHTTPTransport {
    private let response: MapHTTPResponse
    private var request: MapHTTPRequest?

    init(response: MapHTTPResponse) { self.response = response }

    func execute(_ request: MapHTTPRequest) async throws -> MapHTTPResponse {
        self.request = request
        return response
    }

    func lastRequest() -> MapHTTPRequest? { request }
}
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `make test-swift`

Expected: FAIL because product/module `BlueBandMapCore` does not exist.

- [ ] **Step 3: Add the target and minimal HTTP boundary**

In `Package.swift`, add the product and targets exactly:

```swift
.library(name: "BlueBandMapCore", targets: ["BlueBandMapCore"]),
```

```swift
.target(
    name: "BlueBandMapCore",
    dependencies: [
        "BlueBandCore",
        .product(name: "Crypto", package: "swift-crypto"),
    ]
),
```

```swift
.testTarget(
    name: "BlueBandMapCoreTests",
    dependencies: ["BlueBandMapCore", "BlueBandCore"]
),
```

Create `HTTPTransport.swift`:

```swift
import Foundation

public struct MapHTTPRequest: Equatable, Sendable {
    public let method: String
    public let url: URL
    public let headers: [String: String]
    public let body: Data

    public init(method: String, url: URL, headers: [String: String], body: Data) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct MapHTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    public func header(named name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

public protocol MapHTTPTransport: Sendable {
    func execute(_ request: MapHTTPRequest) async throws -> MapHTTPResponse
}
```

- [ ] **Step 4: Run the focused suite to verify it passes**

Run: `make test-swift`

Expected: PASS, including `HTTPTransportTests`.

- [ ] **Step 5: Commit the target boundary**

```bash
git add packages/BlueBandKit/Package.swift packages/BlueBandKit/Sources/BlueBandMapCore packages/BlueBandKit/Tests/BlueBandMapCoreTests
git commit -m "feat: add portable map provider boundary"
```

## Task 2: Validate and identify bounded PNG assets

**Files:**
- Create: `packages/BlueBandKit/Sources/BlueBandMapCore/PNGInspector.swift`
- Create: `packages/BlueBandKit/Sources/BlueBandMapCore/MapAsset.swift`
- Create: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/MapAssetTests.swift`

- [ ] **Step 1: Write failing PNG and hash tests**

Create `MapAssetTests.swift`:

```swift
import Foundation
import XCTest
@testable import BlueBandMapCore

final class MapAssetTests: XCTestCase {
    func testAcceptsPNGWithExpectedIHDRAndStableSHA256Identity() throws {
        let png = makePNGHeader(width: 212, height: 360) + Data([0x49, 0x45, 0x4E, 0x44])
        let asset = try MapAsset.png(data: png, expectedWidth: 212, expectedHeight: 360)

        XCTAssertEqual(asset.mimeType, "image/png")
        XCTAssertEqual(asset.width, 212)
        XCTAssertEqual(asset.height, 360)
        XCTAssertEqual(asset.byteCount, png.count)
        XCTAssertEqual(asset.sha256.count, 64)
        XCTAssertEqual(asset.id, "m1-" + String(asset.sha256.prefix(16)))
    }

    func testRejectsWrongSignatureDimensionsAndOversizedResponse() {
        XCTAssertThrowsError(try MapAsset.png(data: Data("not-png".utf8), expectedWidth: 212, expectedHeight: 360))
        XCTAssertThrowsError(try MapAsset.png(data: makePNGHeader(width: 211, height: 360), expectedWidth: 212, expectedHeight: 360))
        XCTAssertThrowsError(try MapAsset.png(data: Data(repeating: 0, count: MapAsset.maximumPNGBytes + 1), expectedWidth: 212, expectedHeight: 360))
    }

    private func makePNGHeader(width: UInt32, height: UInt32) -> Data {
        var bytes: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82]
        bytes += width.bigEndianBytes
        bytes += height.bigEndianBytes
        return Data(bytes)
    }
}

private extension UInt32 {
    var bigEndianBytes: [UInt8] {
        [UInt8((self >> 24) & 0xff), UInt8((self >> 16) & 0xff), UInt8((self >> 8) & 0xff), UInt8(self & 0xff)]
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `make test-swift`

Expected: FAIL because `MapAsset` and `PNGInspector` are undefined.

- [ ] **Step 3: Implement strict PNG inspection and asset hashing**

Create `PNGInspector.swift`:

```swift
import Foundation

enum PNGInspector {
    enum Error: Swift.Error, Equatable { case truncated, invalidSignature, missingIHDR }
    private static let signature = Data([137, 80, 78, 71, 13, 10, 26, 10])

    static func dimensions(of data: Data) throws -> (width: Int, height: Int) {
        guard data.count >= 24 else { throw Error.truncated }
        guard data.prefix(8) == signature else { throw Error.invalidSignature }
        guard data[12..<16] == Data("IHDR".utf8) else { throw Error.missingIHDR }
        return (
            width: Int(readUInt32(data, offset: 16)),
            height: Int(readUInt32(data, offset: 20))
        )
    }

    private static func readUInt32(_ data: Data, offset: Int) -> UInt32 {
        data[offset..<(offset + 4)].reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
```

Create `MapAsset.swift`:

```swift
import Crypto
import Foundation

public struct MapAsset: Equatable, Sendable {
    public enum Error: Swift.Error, Equatable { case empty, tooLarge, wrongDimensions }
    public static let maximumPNGBytes = 200 * 1_024

    public let id: String
    public let mimeType: String
    public let width: Int
    public let height: Int
    public let data: Data
    public let sha256: String
    public var byteCount: Int { data.count }

    public static func png(data: Data, expectedWidth: Int, expectedHeight: Int) throws -> Self {
        guard !data.isEmpty else { throw Error.empty }
        guard data.count <= maximumPNGBytes else { throw Error.tooLarge }
        let dimensions = try PNGInspector.dimensions(of: data)
        guard dimensions.width == expectedWidth, dimensions.height == expectedHeight else {
            throw Error.wrongDimensions
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return Self(
            id: "m1-" + String(digest.prefix(16)),
            mimeType: "image/png",
            width: dimensions.width,
            height: dimensions.height,
            data: data,
            sha256: digest
        )
    }
}
```

- [ ] **Step 4: Run the portable tests**

Run: `make test-swift`

Expected: PASS with wrong signature, wrong dimensions, oversized data and stable hash covered.

- [ ] **Step 5: Commit PNG asset behavior**

```bash
git add packages/BlueBandKit/Sources/BlueBandMapCore packages/BlueBandKit/Tests/BlueBandMapCoreTests
git commit -m "feat: validate bounded PNG map assets"
```

## Task 3: Implement the Vietmap Static Map contract

**Files:**
- Create: `packages/BlueBandKit/Sources/BlueBandMapCore/VietmapStaticMapClient.swift`
- Create: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/VietmapStaticMapClientTests.swift`

- [ ] **Step 1: Write failing request, response and quota-error tests**

Create `VietmapStaticMapClientTests.swift` with a fake transport and synthetic 212×360 PNG header. Assert all of these exact behaviors:

```swift
func testBuildsDocumentedMultipartPOSTAndReturnsValidatedPNG() async throws {
    let png = makePNG(width: 212, height: 360)
    let transport = QueueHTTPTransport(responses: [
        MapHTTPResponse(statusCode: 200, headers: ["Content-Type": "image/png"], body: png)
    ])
    let client = VietmapStaticMapClient(transport: transport, boundary: "blueband-boundary")
    let request = StaticMapRequest(latitude: 10.759157, longitude: 106.675859, zoom: 17, width: 212, height: 360)

    let asset = try await client.fetch(request, serviceKey: "service-test-key")
    let sent = try XCTUnwrap(await transport.requests().first)
    let body = String(decoding: sent.body, as: UTF8.self)

    XCTAssertEqual(sent.method, "POST")
    XCTAssertEqual(sent.url.absoluteString, "https://maps.vietmap.vn/api/maps/statics/tm")
    XCTAssertEqual(sent.headers["Content-Type"], "multipart/form-data; boundary=blueband-boundary")
    XCTAssertTrue(body.contains("name=\"lat\"\r\n\r\n10.759157"))
    XCTAssertTrue(body.contains("name=\"lng\"\r\n\r\n106.675859"))
    XCTAssertTrue(body.contains("name=\"apikey\"\r\n\r\nservice-test-key"))
    XCTAssertTrue(body.contains("name=\"zoom\"\r\n\r\n17"))
    XCTAssertTrue(body.contains("name=\"size\"\r\n\r\n212x360"))
    XCTAssertEqual(asset.data, png)
}

func testRejectsMissingKeyHTTP429WrongMimeAndInvalidCoordinates() async {
    let request = StaticMapRequest(latitude: 10.759157, longitude: 106.675859, zoom: 17, width: 212, height: 360)
    let rateLimited = VietmapStaticMapClient(
        transport: QueueHTTPTransport(responses: [MapHTTPResponse(statusCode: 429, headers: [:], body: Data())]),
        boundary: "b"
    )
    await XCTAssertThrowsErrorAsync(try await rateLimited.fetch(request, serviceKey: "service-test-key")) { error in
        XCTAssertEqual(error as? VietmapStaticMapError, .rateLimited)
    }
    await XCTAssertThrowsErrorAsync(try await rateLimited.fetch(request, serviceKey: "   "))
    XCTAssertThrowsError(try StaticMapRequest(validatingLatitude: 91, longitude: 106, zoom: 17, width: 212, height: 360))
}
```

Define the small async assertion helper in the test file:

```swift
private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ verify: (Swift.Error) -> Void = { _ in }
) async {
    do { _ = try await expression(); XCTFail("Expected error") }
    catch { verify(error) }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `make test-swift`

Expected: FAIL because the Vietmap client contract is absent.

- [ ] **Step 3: Implement the request and response contract**

Create `VietmapStaticMapClient.swift` with these public types and exact policies:

```swift
import Foundation

public enum VietmapStaticMapError: Swift.Error, Equatable {
    case invalidRequest
    case missingServiceKey
    case rateLimited
    case httpStatus(Int)
    case wrongContentType
}

public struct StaticMapRequest: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let zoom: Int
    public let width: Int
    public let height: Int

    public init(latitude: Double, longitude: Double, zoom: Int, width: Int, height: Int) {
        self.latitude = latitude
        self.longitude = longitude
        self.zoom = zoom
        self.width = width
        self.height = height
    }

    public init(validatingLatitude latitude: Double, longitude: Double, zoom: Int, width: Int, height: Int) throws {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude), (0...20).contains(zoom),
              width == 212, height == 360 else { throw VietmapStaticMapError.invalidRequest }
        self.init(latitude: latitude, longitude: longitude, zoom: zoom, width: width, height: height)
    }
}

public protocol StaticMapProviding: Sendable {
    func fetch(_ request: StaticMapRequest, serviceKey: String) async throws -> MapAsset
}

public struct VietmapStaticMapClient: StaticMapProviding, Sendable {
    private let transport: any MapHTTPTransport
    private let boundary: String

    public init(transport: any MapHTTPTransport, boundary: String = "blueband-map-m1") {
        self.transport = transport
        self.boundary = boundary
    }

    public func fetch(_ request: StaticMapRequest, serviceKey: String) async throws -> MapAsset {
        _ = try StaticMapRequest(
            validatingLatitude: request.latitude, longitude: request.longitude, zoom: request.zoom,
            width: request.width, height: request.height
        )
        let key = serviceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.utf8.count <= 512 else { throw VietmapStaticMapError.missingServiceKey }
        let url = URL(string: "https://maps.vietmap.vn/api/maps/statics/tm")!
        let fields = [
            ("lat", decimal(request.latitude)), ("lng", decimal(request.longitude)),
            ("apikey", key), ("zoom", String(request.zoom)), ("size", "\(request.width)x\(request.height)"),
        ]
        let response = try await transport.execute(MapHTTPRequest(
            method: "POST", url: url,
            headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"],
            body: multipart(fields)
        ))
        if response.statusCode == 429 { throw VietmapStaticMapError.rateLimited }
        guard response.statusCode == 200 else { throw VietmapStaticMapError.httpStatus(response.statusCode) }
        guard response.header(named: "Content-Type")?.lowercased().hasPrefix("image/png") == true else {
            throw VietmapStaticMapError.wrongContentType
        }
        return try MapAsset.png(data: response.body, expectedWidth: request.width, expectedHeight: request.height)
    }

    private func multipart(_ fields: [(String, String)]) -> Data {
        var text = ""
        for (name, value) in fields {
            text += "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"
        }
        text += "--\(boundary)--\r\n"
        return Data(text.utf8)
    }

    private func decimal(_ value: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `make test-swift`

Expected: PASS; the dummy key appears only in test memory and no live request is made.

- [ ] **Step 5: Commit the provider contract**

```bash
git add packages/BlueBandKit/Sources/BlueBandMapCore packages/BlueBandKit/Tests/BlueBandMapCoreTests
git commit -m "feat: add Vietmap static map contract"
```

## Task 4: Persist both Vietmap keys and remembered connection metadata

**Files:**
- Create: `apps/ios/Adapters/Keychain/KeychainVietmapKeyStore.swift`
- Modify: `apps/ios/Adapters/Keychain/UserDefaultsRememberedBandStore.swift`
- Modify: `apps/ios/Tests/KeychainStoreTests.swift`
- Modify: `apps/ios/Tests/RememberedBandStoreTests.swift`

- [ ] **Step 1: Add failing Apple-boundary tests first**

Add these tests before implementation:

```swift
func testVietmapKeysUseIndependentAccountsAndThisDeviceOnlyStorage() throws {
    let client = FakeKeychainClient()
    client.updateStatus = errSecItemNotFound
    let store = KeychainVietmapKeyStore(client: client)

    try store.save("tile-test-key", kind: .tileMap)
    try store.save("service-test-key", kind: .service)

    XCTAssertEqual(client.addedItems.count, 2)
    XCTAssertEqual(client.addedItems[0][kSecAttrAccount] as? String, "vietmap-tilemap-key")
    XCTAssertEqual(client.addedItems[1][kSecAttrAccount] as? String, "vietmap-service-key")
    XCTAssertTrue(client.addedItems.allSatisfy {
        $0[kSecAttrAccessible] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
    })
}
```

Update `FakeKeychainClient` from one `added` item to an array:

```swift
var addedItems: [[CFString: Any]] = []
func add(_ attributes: CFDictionary) -> OSStatus {
    if let item = attributes as? [CFString: Any] { addedItems.append(item) }
    return addStatus
}
```

Update both existing assertions that inspect `client.added` to inspect the last captured item instead:

```swift
let item = try XCTUnwrap(client.addedItems.last)
```

Update the remembered-band test to construct and compare:

```swift
let connectedAt = Date(timeIntervalSince1970: 1_788_000_000)
let band = RememberedBand(id: UUID(), name: "Xiaomi Smart Band 10", lastConnectedAt: connectedAt)
```

- [ ] **Step 2: Record expected Apple-boundary failure**

Run: `make test-ios-metadata`

Expected locally: PASS metadata only. The new XCTest is expected to fail to compile at the GitHub Apple boundary because `KeychainVietmapKeyStore` and the new `RememberedBand` initializer do not exist. Do not write implementation before these tests are committed or staged ahead of the implementation diff.

- [ ] **Step 3: Implement the two-key store**

Create `KeychainVietmapKeyStore.swift`:

```swift
import Foundation
import Security

enum VietmapKeyKind: Equatable, Sendable { case tileMap, service }

protocol VietmapKeyStoreProtocol: Sendable {
    func load(_ kind: VietmapKeyKind) throws -> String?
    func save(_ value: String, kind: VietmapKeyKind) throws
    func delete(_ kind: VietmapKeyKind) throws
}

struct KeychainVietmapKeyStore: VietmapKeyStoreProtocol, Sendable {
    enum StoreError: Swift.Error, Equatable { case invalidValue, invalidStoredValue, unexpectedStatus(OSStatus) }
    private let service: String
    private let client: any KeychainClient

    init(service: String = "dev.lordierclaw.bluebandmap.vietmap", client: any KeychainClient = SystemKeychainClient()) {
        self.service = service
        self.client = client
    }

    func load(_ kind: VietmapKeyKind) throws -> String? {
        var query = baseQuery(kind)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = client.copyMatching(query as CFDictionary, result: &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError.unexpectedStatus(status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty else {
            throw StoreError.invalidStoredValue
        }
        return value
    }

    func save(_ value: String, kind: VietmapKeyKind) throws {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.utf8.count <= 512 else { throw StoreError.invalidValue }
        let attributes: [CFString: Any] = [kSecValueData: Data(normalized.utf8)]
        let update = client.update(baseQuery(kind) as CFDictionary, attributes: attributes as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw StoreError.unexpectedStatus(update) }
        var item = baseQuery(kind)
        item[kSecValueData] = Data(normalized.utf8)
        item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let add = client.add(item as CFDictionary)
        guard add == errSecSuccess else { throw StoreError.unexpectedStatus(add) }
    }

    func delete(_ kind: VietmapKeyKind) throws {
        let status = client.delete(baseQuery(kind) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError.unexpectedStatus(status) }
    }

    private func baseQuery(_ kind: VietmapKeyKind) -> [CFString: Any] {
        let account = kind == .tileMap ? "vietmap-tilemap-key" : "vietmap-service-key"
        return [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }
}
```

- [ ] **Step 4: Add last successful connection date without changing trust semantics**

Change `RememberedBand` and its store:

```swift
struct RememberedBand: Equatable, Sendable {
    let id: UUID
    let name: String
    let lastConnectedAt: Date
}
```

Add key `rememberedBand.lastConnectedAt`, require it in `load()`, write it in `save()`, and remove it in `forget()`. Keep the existing lock and unrelated-key test.

- [ ] **Step 5: Run canonical local checks and Apple CI when available**

Run: `make test && make lint`

Expected locally: PASS. At the Apple boundary, `KeychainStoreTests` and `RememberedBandStoreTests` PASS.

- [ ] **Step 6: Commit persistent configuration storage**

```bash
git add apps/ios/Adapters/Keychain apps/ios/Tests/KeychainStoreTests.swift apps/ios/Tests/RememberedBandStoreTests.swift
git commit -m "feat: persist Vietmap keys and band metadata"
```

## Task 5: Add compact Config and Band picker UI

**Files:**
- Create: `apps/ios/App/ConfigView.swift`
- Create: `apps/ios/App/BandPickerView.swift`
- Create: `apps/ios/App/BandCandidateOrdering.swift`
- Create: `apps/ios/Tests/BandCandidateOrderingTests.swift`
- Modify: `apps/ios/App/AppModel.swift`
- Modify: `apps/ios/App/ContentView.swift`
- Modify: `apps/ios/App/BlueBandMapApp.swift`

- [ ] **Step 1: Write the remembered-first ordering test**

```swift
import XCTest
import BlueBandCore
@testable import BlueBandMap

final class BandCandidateOrderingTests: XCTestCase {
    func testRememberedBandIsFirstThenCandidatesAreRSSISortedAndBounded() {
        let rememberedID = UUID()
        let remembered = RememberedBand(id: rememberedID, name: "Band 10", lastConnectedAt: .distantPast)
        let candidates = (0..<25).map { index in
            BandCandidate(id: index == 7 ? rememberedID : UUID(), name: "BLE \(index)", rssi: -index)
        }

        let result = BandCandidateOrdering.order(candidates, remembered: remembered)

        XCTAssertEqual(result.count, 20)
        XCTAssertEqual(result.first?.id, rememberedID)
        XCTAssertEqual(result.dropFirst().map(\.rssi), result.dropFirst().map(\.rssi).sorted(by: >))
    }

    func testAddsRememberedCandidateWhenScanHasNotRediscoveredIt() {
        let remembered = RememberedBand(id: UUID(), name: "Band 10", lastConnectedAt: .distantPast)
        let result = BandCandidateOrdering.order([], remembered: remembered)
        XCTAssertEqual(result, [BandCandidate(id: remembered.id, name: remembered.name, rssi: nil)])
    }
}
```

- [ ] **Step 2: Implement the pure ordering policy**

```swift
import BlueBandCore

enum BandCandidateOrdering {
    static func order(_ candidates: [BandCandidate], remembered: RememberedBand?) -> [BandCandidate] {
        var unique = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        if let remembered, unique[remembered.id] == nil {
            unique[remembered.id] = BandCandidate(id: remembered.id, name: remembered.name, rssi: nil)
        }
        let rememberedID = remembered?.id
        return Array(unique.values.sorted {
            if $0.id == rememberedID { return true }
            if $1.id == rememberedID { return false }
            return ($0.rssi ?? Int.min) > ($1.rssi ?? Int.min)
        }.prefix(20))
    }
}
```

- [ ] **Step 3: Add AppModel configuration state and actions**

Add these published properties and dependency:

```swift
@Published var tileMapKeyInput = ""
@Published var serviceKeyInput = ""
@Published private(set) var hasTileMapKey = false
@Published private(set) var hasServiceKey = false
private let vietmapKeyStore: any VietmapKeyStoreProtocol

var pickerCandidates: [BandCandidate] {
    BandCandidateOrdering.order(candidates, remembered: rememberedBand)
}
```

Initialize key-health booleans with `load(.tileMap)` and `load(.service)`. Add explicit actions:

```swift
func saveVietmapKey(_ kind: VietmapKeyKind) {
    errorMessage = nil
    do {
        let value = kind == .tileMap ? tileMapKeyInput : serviceKeyInput
        try vietmapKeyStore.save(value, kind: kind)
        if kind == .tileMap { tileMapKeyInput = ""; hasTileMapKey = true }
        else { serviceKeyInput = ""; hasServiceKey = true }
    } catch { errorMessage = "Vietmap key không hợp lệ hoặc không lưu được vào Keychain." }
}

func deleteVietmapKey(_ kind: VietmapKeyKind) {
    do {
        try vietmapKeyStore.delete(kind)
        if kind == .tileMap { tileMapKeyInput = ""; hasTileMapKey = false }
        else { serviceKeyInput = ""; hasServiceKey = false }
    } catch { errorMessage = "Không xóa được Vietmap key khỏi Keychain." }
}
```

When a connection succeeds, construct `RememberedBand` with `Date()`.

- [ ] **Step 4: Implement ConfigView as a separate sheet**

`ConfigView` must contain three masked fields with independent Save/Clear actions, remembered Band name, shortened UUID, last-connected date, and Forget Band. Use this exact UUID helper so the full identifier is not displayed:

```swift
private func shortID(_ id: UUID) -> String {
    let raw = id.uuidString
    return "\(raw.prefix(4))…\(raw.suffix(4))"
}
```

All key fields use `SecureField`, disable autocorrection/capitalization, clear their bindings after save, and show only `Đã lưu trong Keychain` status. No reveal button is added in M1.

- [ ] **Step 5: Implement BandPickerView as a sheet/dialog**

The picker renders `model.pickerCandidates`, marks `candidate.id == model.rememberedBand?.id` with a star, shows name/RSSI/short UUID, and uses `.task { await model.scan() }`. Candidate selection calls `await model.connect(to:)`; dismiss only after state advances beyond `.idle`/`.scanning`. Add Rescan, Stop and Close controls. The main `ContentView` Connect action only presents this picker; it no longer renders the candidate list inline.

- [ ] **Step 6: Compose dependencies and run checks**

Pass `KeychainVietmapKeyStore()` into `AppModel` in `BlueBandMapApp`. Run:

`make test && make lint`

Expected locally: PASS. Apple CI compiles both SwiftUI sheets and runs ordering/keychain tests.

- [ ] **Step 7: Commit the configure-once workflow**

```bash
git add apps/ios/App apps/ios/Tests/BandCandidateOrderingTests.swift
git commit -m "feat: add persistent config and band picker"
```

## Task 6: Add awaitable application acknowledgement

**Files:**
- Modify: `packages/BlueBandKit/Sources/BlueBandCore/InterconnectSession.swift`
- Modify: `packages/BlueBandKit/Sources/BlueBandCore/BandSession.swift`
- Modify: `packages/BlueBandKit/Tests/BlueBandCoreTests/InterconnectSessionTests.swift`

- [ ] **Step 1: Write failing acknowledgement and timeout tests**

Add one test that starts `sendAwaitingAcknowledgement`, waits until the command recorder has the outgoing envelope, feeds the matching Band ACK, and asserts the returned ID. Add a second test with `ImmediateRecordingClock` and assert `InterconnectDeliveryError.timeout("i-test")`. Add a disconnect test asserting `InterconnectDeliveryError.disconnected`.

- [ ] **Step 2: Run focused portable tests to verify failure**

Run: `make test-swift`

Expected: FAIL because `sendAwaitingAcknowledgement` and `InterconnectDeliveryError` do not exist.

- [ ] **Step 3: Implement waiter registration before transmission**

Add:

```swift
public enum InterconnectDeliveryError: Swift.Error, Equatable, Sendable {
    case timeout(String)
    case disconnected
}
```

Store `deliveryWaiters: [String: CheckedContinuation<String, Swift.Error>]`. Implement:

```swift
public func sendAwaitingAcknowledgement(topic: String, body: [String: JSONValue]) async throws -> String {
    guard let identity else { throw Error.notReady }
    let envelope = ApplicationEnvelope.message(id: idGenerator(), source: .ios, topic: topic, body: body)
    let encoded = try envelope.encoded()
    return try await withCheckedThrowingContinuation { continuation in
        deliveryWaiters[envelope.id] = continuation
        Task { [weak self] in
            await self?.transmitAwaited(envelope, encoded: encoded, identity: identity)
        }
    }
}
```

`transmitAwaited` sends the existing `ThirdPartyAppCodec.phoneMessage`, emits `.sent`, and starts the same five-second clock. On send error, remove/resume the waiter before yielding `.failed`. On matching ACK, cancel timeout, emit `.acknowledged`, and resume the waiter. On timeout, resume with `.timeout(id)` and yield `.failed`. On disconnect, resume all waiters with `.disconnected` before clearing them. Keep existing non-awaiting `send` behavior and event order unchanged.

Add a forwarding method to `BandSession`:

```swift
public func sendAwaitingAcknowledgement(topic: String, body: [String: JSONValue]) async throws -> String {
    guard let interconnect else { throw BandSessionError.notConnected }
    return try await interconnect.sendAwaitingAcknowledgement(topic: topic, body: body)
}
```

- [ ] **Step 4: Run all Swift tests**

Run: `make test-swift`

Expected: PASS, including legacy send/timeout behavior and new waiter behavior.

- [ ] **Step 5: Commit without changing application bytes**

```bash
git add packages/BlueBandKit/Sources/BlueBandCore packages/BlueBandKit/Tests/BlueBandCoreTests
git commit -m "feat: await application acknowledgements"
```

## Task 7: Create a 512-byte-safe map asset transfer plan

**Files:**
- Create: `packages/BlueBandKit/Sources/BlueBandMapCore/MapAssetTransferPlan.swift`
- Create: `packages/BlueBandKit/Tests/BlueBandMapCoreTests/MapAssetTransferPlanTests.swift`

- [ ] **Step 1: Write failing reconstruction and envelope-bound tests**

The test creates a deterministic 1,001-byte PNG-shaped value by appending bytes to `makePNGHeader(width: 212, height: 360)`, constructs it through `MapAsset.png`, calls `MapAssetTransferPlan.make`, asserts begin/chunk/end ordering, reconstructs Base64 chunks by offset, and encodes every body in an `ApplicationEnvelope` whose ID is 32 printable bytes. Every envelope must be at most 512 bytes.

- [ ] **Step 2: Run the test to verify failure**

Run: `make test-swift`

Expected: FAIL because the transfer plan is absent.

- [ ] **Step 3: Implement dynamic chunk sizing**

Define:

```swift
import Foundation
import BlueBandCore

public struct MapTransferStep: Equatable, Sendable {
    public let topic: String
    public let body: [String: JSONValue]
}

public enum MapAssetTransferPlan {
    public enum Error: Swift.Error, Equatable { case cannotFitChunk }

    public static func make(asset: MapAsset) throws -> [MapTransferStep] {
        let begin = MapTransferStep(topic: "map.asset.begin", body: [
            "asset": .string(asset.id), "bytes": .number(Double(asset.byteCount)),
            "mime": .string(asset.mimeType), "sha256": .string(asset.sha256),
            "width": .number(Double(asset.width)), "height": .number(Double(asset.height)),
        ])
        var result = [begin]
        var offset = 0
        while offset < asset.data.count {
            let length = try maximumFittingLength(asset: asset, offset: offset)
            let chunk = asset.data[offset..<min(offset + length, asset.data.count)]
            result.append(MapTransferStep(topic: "map.asset.chunk", body: [
                "asset": .string(asset.id), "offset": .number(Double(offset)),
                "data": .string(Data(chunk).base64EncodedString()),
            ]))
            offset += chunk.count
        }
        result.append(MapTransferStep(topic: "map.asset.end", body: ["asset": .string(asset.id)]))
        return result
    }

    private static func maximumFittingLength(asset: MapAsset, offset: Int) throws -> Int {
        var low = 1
        var high = min(320, asset.data.count - offset)
        var best = 0
        while low <= high {
            let candidate = (low + high) / 2
            let body: [String: JSONValue] = [
                "asset": .string(asset.id), "offset": .number(Double(offset)),
                "data": .string(Data(asset.data[offset..<offset + candidate]).base64EncodedString()),
            ]
            let envelope = ApplicationEnvelope.message(
                id: String(repeating: "x", count: 32), source: .ios, topic: "map.asset.chunk", body: body
            )
            if (try? envelope.encoded()) != nil { best = candidate; low = candidate + 1 }
            else { high = candidate - 1 }
        }
        guard best > 0 else { throw Error.cannotFitChunk }
        return best
    }
}
```

- [ ] **Step 4: Run tests**

Run: `make test-swift`

Expected: PASS with exact byte reconstruction and all envelopes within 512 bytes.

- [ ] **Step 5: Commit the application-level transfer plan**

```bash
git add packages/BlueBandKit/Sources/BlueBandMapCore packages/BlueBandKit/Tests/BlueBandMapCoreTests
git commit -m "feat: plan bounded map asset chunks"
```

## Task 8: Receive, verify and display M1 on Band

**Files:**
- Modify: `apps/band/src/manifest.json`
- Modify: `apps/band/src/pages/index/index.ux`
- Modify: `apps/band/test/bundle-contract.test.mjs`
- Modify: `apps/band/test/envelope-page.test.mjs`

- [ ] **Step 1: Write failing Band runtime tests**

Extend the page loader to remove/inject all three imports:

```javascript
.replace(/import file from ["']@system\.file["']/, "")
.replace(/import crypto from ["']@system\.crypto["']/, "")
```

Construct the component with `new Function("interconnect", "file", "crypto", script)`. Add a test that sends begin, two ordered chunks, and end. The fake file writes bytes by offset; fake crypto returns the expected 64-character digest for the URI. Assert:

- Each valid message is ACKed only after its operation succeeds.
- `page.mapReady === true`.
- For a fixture whose validated asset ID is `m1-0123456789abcdef`, `page.mapPath === "internal://files/m1-0123456789abcdef.png"`.
- Band emits `map.asset.result` with `status: "ok"`, byte count and digest prefix.
- Repeating the same message ID is ACKed but does not write twice.

Add failure tests for wrong offset, wrong final length and digest mismatch; each emits one stable `ASSET_*` result and never sets `mapReady`.

- [ ] **Step 2: Update the manifest contract test first**

Expect version `0.2.0`, version code `2`, and exactly these features:

```javascript
[
  { name: "system.interconnect" },
  { name: "system.file" },
  { name: "system.crypto" }
]
```

Run: `make test-rpk`

Expected: FAIL because manifest/page do not yet implement M1.

- [ ] **Step 3: Implement ordered write and SHA-256 publication**

In the one-page RPK:

- Import `file` and `crypto`.
- Add bounded constants: max 200 KiB, width 212, height 360, SHA-256 regex, and one active transfer.
- Validate begin fields before deleting/recreating the destination URI.
- Convert Base64 to `Uint8Array` through `crypto.atob` and character codes.
- Require each chunk offset to equal `receivedBytes`; reject gaps and overlap.
- Call `file.writeArrayBuffer({uri, buffer, position: offset})` and ACK the chunk only in `success`.
- On end, require exact byte count, call `crypto.hashDigest({uri, algo: "SHA256"})`, normalize lowercase and compare to the declared 64-hex digest.
- Set `mapPath`/`mapReady` only after the digest matches.
- ACK end and send `map.asset.result` with `status`, `bytes`, `sha256Prefix`, and stable error code when applicable.
- Remember message IDs only after successful handling so a failed write is not falsely deduplicated.

Add the image element:

```html
<image class="map" if="{{ mapReady }}" src="{{ mapPath }}" object-fit="contain" @complete="mapComplete" @error="mapError" />
```

Keep the waiting/connection diagnostics and `system.echo` regression path. Display `M1 MAP READY` plus the 8-character hash prefix above the image.

- [ ] **Step 4: Run RPK tests and archive verification**

Run: `make test-rpk`

Expected: PASS for success, duplicate, offset, length, digest, manifest and real RPK build tests.

- [ ] **Step 5: Commit Band M1 receiver**

```bash
git add apps/band
git commit -m "feat: verify and display M1 map asset"
```

## Task 9: Wire live HTTPS and iOS M1 orchestration

**Files:**
- Create: `apps/ios/Adapters/Vietmap/URLSessionHTTPTransport.swift`
- Create: `apps/ios/App/M1State.swift`
- Modify: `apps/ios/App/AppModel.swift`
- Modify: `apps/ios/App/BlueBandMapApp.swift`
- Modify: `apps/ios/App/ContentView.swift`
- Modify: `apps/ios/project.yml`
- Modify: `apps/ios/Tests/ProjectSmokeTests.swift`

- [ ] **Step 1: Add failing composition tests**

Add project smoke assertions for the fixed M1 request and state labels without using a real key or network:

```swift
func testM1UsesOneDocumentedStaticMapRequest() throws {
    XCTAssertEqual(M1Configuration.request.latitude, 10.759157, accuracy: 0.000001)
    XCTAssertEqual(M1Configuration.request.longitude, 106.675859, accuracy: 0.000001)
    XCTAssertEqual(M1Configuration.request.zoom, 17)
    XCTAssertEqual(M1Configuration.request.width, 212)
    XCTAssertEqual(M1Configuration.request.height, 360)
    XCTAssertEqual(M1Configuration.maximumProviderCalls, 1)
}
```

Add `BlueBandMapCore` as an app dependency in `project.yml` only after the test exists.

- [ ] **Step 2: Implement URLSession transport without logging**

```swift
import Foundation
import BlueBandMapCore

struct URLSessionHTTPTransport: MapHTTPTransport {
    func execute(_ request: MapHTTPRequest) async throws -> MapHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        let headers = Dictionary(uniqueKeysWithValues: http.allHeaderFields.compactMap { key, value in
            guard let key = key as? String else { return nil }
            return (key, String(describing: value))
        })
        return MapHTTPResponse(statusCode: http.statusCode, headers: headers, body: data)
    }
}
```

- [ ] **Step 3: Define explicit M1 state**

```swift
import BlueBandMapCore

enum M1State: Equatable {
    case idle
    case fetching
    case transferring(completed: Int, total: Int)
    case waitingForBand(assetID: String, hashPrefix: String)
    case displayed(assetID: String, hashPrefix: String)
    case failed(code: String)
}

enum M1Configuration {
    static let request = StaticMapRequest(latitude: 10.759157, longitude: 106.675859, zoom: 17, width: 212, height: 360)
    static let maximumProviderCalls = 1
}
```

- [ ] **Step 4: Add one user-triggered AppModel operation**

Inject `StaticMapProviding` and publish `m1State`. `startM1()` must:

1. Require `rpkState == .ready`.
2. Load only the Service key from Keychain.
3. Set `.fetching` and make exactly one `fetch` call.
4. Build `MapAssetTransferPlan`.
5. Send each step with `session.sendAwaitingAcknowledgement`, updating completed/total after each ACK.
6. Set `.waitingForBand` after the end ACK.
7. Map 429 to `PROVIDER_RATE_LIMITED`; MIME/status/request failures to stable `PROVIDER_*`; transfer timeout/disconnect to stable `TRANSFER_*`; asset errors to stable `ASSET_*`.
8. Perform no automatic retry. A second button press is the explicit Retry.

In `consume(_:)`, parse only a valid `map.asset.result` body from Band. Require matching expected asset ID. Set `.displayed` only for `status == "ok"`; otherwise set `.failed(code:)`. The generic envelope ACK still occurs in `InterconnectSession`.

- [ ] **Step 5: Add the M1 UI section**

Show:

- `M1 · One Vietmap street PNG`.
- Provider budget `Tối đa 1 Static Map request mỗi lần bấm`.
- Current safe state/progress.
- `Tải và gửi M1` when idle/failed/displayed.
- No automatic request on app launch, sheet appearance, connection or RPK open.
- Disable while fetching/transferring/waiting.

- [ ] **Step 6: Compose and verify**

Create `VietmapStaticMapClient(transport: URLSessionHTTPTransport())`, pass it and `KeychainVietmapKeyStore` into `AppModel`, update the XcodeGen dependency, then run:

`make test && make lint`

Expected locally: PASS. Apple CI compiles URLSession/SwiftUI composition and ProjectSmokeTests pass. No live Vietmap request occurs in CI.

- [ ] **Step 7: Commit the M1 iOS path**

```bash
git add apps/ios packages/BlueBandKit/Package.swift
git commit -m "feat: send Vietmap M1 map from iPhone"
```

## Task 10: Produce the M1 owner test packet and final verification

**Files:**
- Create: `docs/testing/results/2026-08-29-m1-test-packet.md`
- Modify: `CHANGELOG.md`
- Modify: `docs/product/overview.md`

- [ ] **Step 1: Write the exact test packet**

The packet must state that it is a procedure, not a result. Include:

- Required build commit, IPA/RPK versions and hashes after artifacts exist.
- iPhone 13 Pro Max, iOS 26, observed Band firmware.
- Mi Fitness closed.
- Saved AuthKey and Vietmap Service key health; TileMap key may be saved but M1 does not consume it.
- Clean install RPK 0.2.0 and launch iOS build.
- Open Config and verify all three values remain saved without revealing them.
- Open Connect dialog, select Band, complete proof and RPK handshake.
- Press M1 exactly five times, waiting for `M1 MAP READY` each time.
- Confirm image content, 8-character hash prefix agreement and no crash.
- Close/reopen the RPK ten times without making another provider request unless the M1 button is pressed.
- Maximum provider calls: five for the five explicit transfers; zero for reload checks.
- Stop immediately on HTTP 429, rate-limit status, corruption, secret exposure, crash or unsafe device interaction.
- Return one evidence status plus redacted diagnostics/screenshots.

- [ ] **Step 2: Update product status without claiming hardware support**

Mark M1 as `Implementation ready for owner hardware acceptance` only after canonical tests pass. Do not mark M1 hardware-confirmed until the owner returns `PASS-HW` with artifact hashes.

- [ ] **Step 3: Run all required verification**

Run exactly:

```bash
make test
make lint
git diff --check
```

Expected: all Swift, RPK, protocol-lab, iOS metadata, shell syntax, no-secret and diff checks PASS. Existing npm audit warnings are recorded but do not justify dependency upgrades inside M1.

- [ ] **Step 4: Review the final diff for forbidden scope**

Run:

```bash
git diff --name-only HEAD~9..HEAD
git status --short
```

Confirm there is no change to verified Xiaomi vectors, SPP/auth/ThirdPartyApp bytes, background modes, Route API, TileMap requests, dependency directories, generated Xcode projects, signing material, `.env` files or real keys.

- [ ] **Step 5: Commit documentation and handoff**

```bash
git add CHANGELOG.md docs/product/overview.md docs/testing/results/2026-08-29-m1-test-packet.md
git commit -m "docs: add M1 hardware test packet"
```

## Plan self-review

- Spec coverage: persistent AuthKey/Vietmap keys, remembered Band metadata, compact picker, provider contract, bounded PNG, dynamic chunk sizing, stop-and-wait ACKs, Band file/hash/image path, explicit provider call budget, error labels and owner test packet are each assigned to a task.
- Scope containment: M2 tile grid, pan, route, SDK and background behavior remain outside this plan.
- Type consistency: `MapHTTPRequest`, `MapHTTPResponse`, `MapHTTPTransport`, `MapAsset`, `StaticMapRequest`, `StaticMapProviding`, `MapTransferStep`, `MapAssetTransferPlan`, `VietmapKeyKind`, `M1State` and `sendAwaitingAcknowledgement` keep one spelling and signature throughout.
- Protocol consistency: all new map messages remain Application Envelope v1 topics at or below 512 encoded bytes; no Xiaomi wire constant changes.
- Security consistency: dummy keys are test-only strings; live keys are Keychain-only and omitted from diagnostics, cache identities and logs.
- Evidence consistency: completion of this plan means implementation is ready for hardware acceptance, not that Band support has already been proven.
