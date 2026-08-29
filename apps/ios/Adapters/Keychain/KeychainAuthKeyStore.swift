import Foundation
import Security
import BlueBandProtocol

protocol AuthKeyStoreProtocol: Sendable {
    func load() throws -> AuthKey?
    func save(_ key: AuthKey) throws
    func delete() throws
}

struct KeychainAuthKeyStore: AuthKeyStoreProtocol, Sendable {
    enum StoreError: Swift.Error, Equatable {
        case unexpectedStatus(OSStatus)
        case invalidStoredValue
    }

    private let service: String
    private let account = "xiaomi-auth-key"
    private let client: any KeychainClient

    init(service: String = "dev.lordierclaw.bluebandmap.auth", client: any KeychainClient = SystemKeychainClient()) {
        self.service = service
        self.client = client
    }

    func load() throws -> AuthKey? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = client.copyMatching(query as CFDictionary, result: &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError.unexpectedStatus(status) }
        guard let data = result as? Data, let key = try? AuthKey(bytes: data) else {
            throw StoreError.invalidStoredValue
        }
        return key
    }

    func save(_ key: AuthKey) throws {
        let attributes: [CFString: Any] = [kSecValueData: key.bytes]
        let update = client.update(baseQuery as CFDictionary, attributes: attributes as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw StoreError.unexpectedStatus(update) }
        var item = baseQuery
        item[kSecValueData] = key.bytes
        item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let add = client.add(item as CFDictionary)
        guard add == errSecSuccess else { throw StoreError.unexpectedStatus(add) }
    }

    func delete() throws {
        let status = client.delete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.unexpectedStatus(status)
        }
    }

    private var baseQuery: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }
}
