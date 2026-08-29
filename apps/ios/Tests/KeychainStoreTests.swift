import Foundation
import Security
import XCTest
import BlueBandProtocol
@testable import BlueBandMap

final class KeychainStoreTests: XCTestCase {
    func testAuthKeyAddsThisDeviceOnlyAndNeverUsesRPKAccount() throws {
        let client = FakeKeychainClient()
        client.updateStatus = errSecItemNotFound
        let store = KeychainAuthKeyStore(client: client)
        try store.save(AuthKey(bytes: Data(repeating: 7, count: 16)))

        let item = try XCTUnwrap(client.addedItems.last)
        XCTAssertEqual(item[kSecAttrAccessible] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        XCTAssertEqual(item[kSecAttrAccount] as? String, "xiaomi-auth-key")
    }

    func testRPKStoreUsesIndependentNamespaceAndSupportsReset() async throws {
        let client = FakeKeychainClient()
        client.updateStatus = errSecItemNotFound
        let store = KeychainTrustedRPKStore(client: client)
        try await store.saveTrustedRPKFingerprint(Data([1, 2, 3]))
        let item = try XCTUnwrap(client.addedItems.last)
        XCTAssertEqual(item[kSecAttrAccount] as? String, "trusted-rpk-fingerprint")
        try await store.resetTrustedRPKFingerprint()
        XCTAssertEqual(client.deleteCount, 1)
    }

    func testVietmapKeysAddIndependentGenericPasswordItemsWithTrimmedValues() throws {
        let client = FakeKeychainClient()
        client.updateStatus = errSecItemNotFound
        let store = KeychainVietmapKeyStore(client: client)

        try store.save("  tile-test-key\n", kind: .tileMap)
        try store.save("\tservice-test-key  ", kind: .service)

        XCTAssertEqual(client.addedItems.count, 2)
        assertVietmapQuery(client.addedItems[0], account: "vietmap-tilemap-key")
        assertVietmapQuery(client.addedItems[1], account: "vietmap-service-key")
        XCTAssertEqual(client.addedItems[0][kSecValueData] as? Data, Data("tile-test-key".utf8))
        XCTAssertEqual(client.addedItems[1][kSecValueData] as? Data, Data("service-test-key".utf8))
        XCTAssertTrue(client.addedItems.allSatisfy {
            $0[kSecAttrAccessible] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        })
    }

    func testVietmapSaveUpdateSuccessDoesNotAdd() throws {
        let client = FakeKeychainClient()
        let store = KeychainVietmapKeyStore(client: client)

        try store.save(" updated-value ", kind: .service)

        XCTAssertTrue(client.addedItems.isEmpty)
        XCTAssertEqual(client.updateQueries.count, 1)
        assertVietmapQuery(client.updateQueries[0], account: "vietmap-service-key")
        XCTAssertEqual(client.updatedAttributes[0][kSecValueData] as? Data, Data("updated-value".utf8))
        XCTAssertEqual(
            client.updatedAttributes[0][kSecAttrAccessible] as? String,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        )
    }

    func testVietmapSaveRejectsInvalidValuesBeforeCallingKeychain() {
        for value in ["", " \n\t ", String(repeating: "a", count: 513), "value\u{0000}"] {
            let client = FakeKeychainClient()
            let store = KeychainVietmapKeyStore(client: client)

            XCTAssertThrowsError(try store.save(value, kind: .tileMap)) { error in
                XCTAssertEqual(error as? KeychainVietmapKeyStore.StoreError, .invalidValue)
            }
            XCTAssertTrue(client.updateQueries.isEmpty)
            XCTAssertTrue(client.addedItems.isEmpty)
            XCTAssertTrue(client.deleteQueries.isEmpty)
            XCTAssertTrue(client.copyQueries.isEmpty)
        }
    }

    func testVietmapSaveMapsUnexpectedUpdateAndAddStatusesExactly() {
        let updateClient = FakeKeychainClient()
        updateClient.updateStatus = errSecAuthFailed
        let updateStore = KeychainVietmapKeyStore(client: updateClient)
        XCTAssertThrowsError(try updateStore.save("value", kind: .tileMap)) { error in
            XCTAssertEqual(error as? KeychainVietmapKeyStore.StoreError, .unexpectedStatus(errSecAuthFailed))
        }

        let addClient = FakeKeychainClient()
        addClient.updateStatus = errSecItemNotFound
        addClient.addStatus = errSecDuplicateItem
        let addStore = KeychainVietmapKeyStore(client: addClient)
        XCTAssertThrowsError(try addStore.save("value", kind: .service)) { error in
            XCTAssertEqual(error as? KeychainVietmapKeyStore.StoreError, .unexpectedStatus(errSecDuplicateItem))
        }
    }

    func testVietmapDeleteIsIdempotentAndMapsUnexpectedStatusExactly() throws {
        let client = FakeKeychainClient()
        let store = KeychainVietmapKeyStore(client: client)

        try store.delete(.tileMap)
        assertVietmapQuery(client.deleteQueries[0], account: "vietmap-tilemap-key")

        client.deleteStatus = errSecItemNotFound
        try store.delete(.service)
        assertVietmapQuery(client.deleteQueries[1], account: "vietmap-service-key")

        client.deleteStatus = errSecInteractionNotAllowed
        XCTAssertThrowsError(try store.delete(.tileMap)) { error in
            XCTAssertEqual(error as? KeychainVietmapKeyStore.StoreError, .unexpectedStatus(errSecInteractionNotAllowed))
        }
    }

    func testVietmapLoadReturnsNilWhenNotFoundAndMapsUnexpectedStatusExactly() throws {
        let client = FakeKeychainClient()
        let store = KeychainVietmapKeyStore(client: client)

        XCTAssertNil(try store.load(.tileMap))
        assertVietmapLoadQuery(client.copyQueries[0], account: "vietmap-tilemap-key")

        client.copyStatus = errSecAuthFailed
        XCTAssertThrowsError(try store.load(.service)) { error in
            XCTAssertEqual(error as? KeychainVietmapKeyStore.StoreError, .unexpectedStatus(errSecAuthFailed))
        }
        assertVietmapLoadQuery(client.copyQueries[1], account: "vietmap-service-key")
    }

    func testVietmapLoadReturnsValidUTF8AndKeepsKindsIndependent() throws {
        let client = FakeKeychainClient()
        client.copyStatus = errSecSuccess
        let store = KeychainVietmapKeyStore(client: client)

        client.copyResult = Data("tile-value".utf8) as CFData
        XCTAssertEqual(try store.load(.tileMap), "tile-value")
        client.copyResult = Data("service-value".utf8) as CFData
        XCTAssertEqual(try store.load(.service), "service-value")

        assertVietmapLoadQuery(client.copyQueries[0], account: "vietmap-tilemap-key")
        assertVietmapLoadQuery(client.copyQueries[1], account: "vietmap-service-key")
    }

    func testVietmapLoadRejectsEmptyAndNonUTF8StoredValues() {
        for data in [Data(), Data([0xFF])] {
            assertVietmapLoadRejects(data as CFData)
        }
    }

    func testVietmapLoadRejectsWhitespaceOnlyStoredValue() {
        assertVietmapLoadRejects(Data(" \n\t ".utf8) as CFData)
    }

    func testVietmapLoadRejectsStoredValueAt513UTF8Bytes() {
        assertVietmapLoadRejects(Data(String(repeating: "a", count: 513).utf8) as CFData)
    }

    func testVietmapLoadRejectsStoredValueContainingASCIIControl() {
        assertVietmapLoadRejects(Data([0x61, 0x00, 0x62]) as CFData)
    }

    func testVietmapLoadRejectsNoncanonicalLeadingOrTrailingWhitespace() {
        assertVietmapLoadRejects(Data(" leading".utf8) as CFData)
        assertVietmapLoadRejects(Data("trailing ".utf8) as CFData)
    }

    func testVietmapLoadRejectsNilSuccessfulCopyResult() {
        assertVietmapLoadRejects(nil)
    }

    func testVietmapLoadRejectsNonDataSuccessfulCopyResult() {
        assertVietmapLoadRejects(NSNumber(value: 7))
    }

    private func assertVietmapQuery(
        _ query: [CFString: Any],
        account: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(query[kSecClass] as? String, kSecClassGenericPassword as String, file: file, line: line)
        XCTAssertEqual(query[kSecAttrService] as? String, "dev.lordierclaw.bluebandmap.vietmap", file: file, line: line)
        XCTAssertEqual(query[kSecAttrAccount] as? String, account, file: file, line: line)
    }

    private func assertVietmapLoadQuery(
        _ query: [CFString: Any],
        account: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertVietmapQuery(query, account: account, file: file, line: line)
        XCTAssertEqual(query[kSecReturnData] as? Bool, true, file: file, line: line)
        XCTAssertEqual(query[kSecMatchLimit] as? String, kSecMatchLimitOne as String, file: file, line: line)
    }

    private func assertVietmapLoadRejects(
        _ copyResult: CFTypeRef?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let client = FakeKeychainClient()
        client.copyStatus = errSecSuccess
        client.copyResult = copyResult
        let store = KeychainVietmapKeyStore(client: client)

        XCTAssertThrowsError(try store.load(.tileMap), file: file, line: line) { error in
            XCTAssertEqual(
                error as? KeychainVietmapKeyStore.StoreError,
                .invalidStoredValue,
                file: file,
                line: line
            )
        }
    }
}

private final class FakeKeychainClient: KeychainClient, @unchecked Sendable {
    var updateStatus: OSStatus = errSecSuccess
    var copyStatus: OSStatus = errSecItemNotFound
    var addStatus: OSStatus = errSecSuccess
    var deleteStatus: OSStatus = errSecSuccess
    var copyResult: CFTypeRef?
    var copyQueries: [[CFString: Any]] = []
    var addedItems: [[CFString: Any]] = []
    var updateQueries: [[CFString: Any]] = []
    var updatedAttributes: [[CFString: Any]] = []
    var deleteQueries: [[CFString: Any]] = []
    var deleteCount: Int { deleteQueries.count }

    func copyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        if let query = query as? [CFString: Any] { copyQueries.append(query) }
        if copyStatus == errSecSuccess { result?.pointee = copyResult }
        return copyStatus
    }

    func add(_ attributes: CFDictionary) -> OSStatus {
        if let item = attributes as? [CFString: Any] { addedItems.append(item) }
        return addStatus
    }

    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        if let query = query as? [CFString: Any] { updateQueries.append(query) }
        if let attributes = attributes as? [CFString: Any] { updatedAttributes.append(attributes) }
        return updateStatus
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        if let query = query as? [CFString: Any] { deleteQueries.append(query) }
        return deleteStatus
    }
}
