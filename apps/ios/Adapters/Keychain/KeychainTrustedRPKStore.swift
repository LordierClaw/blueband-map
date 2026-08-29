import Foundation
import Security
import BlueBandCore

struct KeychainTrustedRPKStore: TrustedRPKStore, Sendable {
    enum StoreError: Swift.Error, Equatable { case unexpectedStatus(OSStatus), invalidStoredValue }
    private let service: String
    private let account = "trusted-rpk-fingerprint"
    private let client: any KeychainClient

    init(service: String = "dev.lordierclaw.bluebandmap.rpk-trust", client: any KeychainClient = SystemKeychainClient()) {
        self.service = service
        self.client = client
    }

    func trustedRPKFingerprint() async throws -> Data? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = client.copyMatching(query as CFDictionary, result: &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError.unexpectedStatus(status) }
        guard let data = result as? Data, !data.isEmpty else { throw StoreError.invalidStoredValue }
        return data
    }

    func saveTrustedRPKFingerprint(_ fingerprint: Data) async throws {
        guard !fingerprint.isEmpty else { throw StoreError.invalidStoredValue }
        let attributes: [CFString: Any] = [kSecValueData: fingerprint]
        let update = client.update(baseQuery as CFDictionary, attributes: attributes as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw StoreError.unexpectedStatus(update) }
        var item = baseQuery
        item[kSecValueData] = fingerprint
        item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let add = client.add(item as CFDictionary)
        guard add == errSecSuccess else { throw StoreError.unexpectedStatus(add) }
    }

    func resetTrustedRPKFingerprint() async throws {
        let status = client.delete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError.unexpectedStatus(status) }
    }

    private var baseQuery: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }
}
