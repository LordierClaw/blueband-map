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

        let item = try XCTUnwrap(client.added as? [CFString: Any])
        XCTAssertEqual(item[kSecAttrAccessible] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        XCTAssertEqual(item[kSecAttrAccount] as? String, "xiaomi-auth-key")
    }

    func testRPKStoreUsesIndependentNamespaceAndSupportsReset() async throws {
        let client = FakeKeychainClient()
        client.updateStatus = errSecItemNotFound
        let store = KeychainTrustedRPKStore(client: client)
        try await store.saveTrustedRPKFingerprint(Data([1, 2, 3]))
        let item = try XCTUnwrap(client.added as? [CFString: Any])
        XCTAssertEqual(item[kSecAttrAccount] as? String, "trusted-rpk-fingerprint")
        try await store.resetTrustedRPKFingerprint()
        XCTAssertEqual(client.deleteCount, 1)
    }
}

private final class FakeKeychainClient: KeychainClient, @unchecked Sendable {
    var updateStatus: OSStatus = errSecSuccess
    var copyStatus: OSStatus = errSecItemNotFound
    var addStatus: OSStatus = errSecSuccess
    var deleteStatus: OSStatus = errSecSuccess
    var added: CFDictionary?
    var deleteCount = 0

    func copyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus { copyStatus }
    func add(_ attributes: CFDictionary) -> OSStatus { added = attributes; return addStatus }
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus { updateStatus }
    func delete(_ query: CFDictionary) -> OSStatus { deleteCount += 1; return deleteStatus }
}
