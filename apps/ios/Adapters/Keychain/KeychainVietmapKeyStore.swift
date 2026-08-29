import Foundation
import Security

enum VietmapKeyKind: Equatable, Sendable {
    case tileMap
    case service
}

protocol VietmapKeyStoreProtocol: Sendable {
    func load(_ kind: VietmapKeyKind) throws -> String?
    func save(_ value: String, kind: VietmapKeyKind) throws
    func delete(_ kind: VietmapKeyKind) throws
}

struct KeychainVietmapKeyStore: VietmapKeyStoreProtocol, Sendable {
    enum StoreError: Swift.Error, Equatable {
        case invalidValue
        case invalidStoredValue
        case unexpectedStatus(OSStatus)
    }

    private let service: String
    private let client: any KeychainClient

    init(
        service: String = "dev.lordierclaw.bluebandmap.vietmap",
        client: any KeychainClient = SystemKeychainClient()
    ) {
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
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            throw StoreError.invalidStoredValue
        }
        return value
    }

    func save(_ value: String, kind: VietmapKeyKind) throws {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.utf8.count <= 512 else {
            throw StoreError.invalidValue
        }

        let data = Data(normalized.utf8)
        let attributes: [CFString: Any] = [kSecValueData: data]
        let updateStatus = client.update(
            baseQuery(kind) as CFDictionary,
            attributes: attributes as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw StoreError.unexpectedStatus(updateStatus)
        }

        var item = baseQuery(kind)
        item[kSecValueData] = data
        item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = client.add(item as CFDictionary)
        guard addStatus == errSecSuccess else {
            throw StoreError.unexpectedStatus(addStatus)
        }
    }

    func delete(_ kind: VietmapKeyKind) throws {
        let status = client.delete(baseQuery(kind) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(_ kind: VietmapKeyKind) -> [CFString: Any] {
        let account = kind == .tileMap ? "vietmap-tilemap-key" : "vietmap-service-key"
        return [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }
}
