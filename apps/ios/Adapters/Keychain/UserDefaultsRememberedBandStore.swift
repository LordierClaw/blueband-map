import Foundation

struct RememberedBand: Equatable, Sendable {
    let id: UUID
    let name: String
    let lastConnectedAt: Date

    init(id: UUID, name: String, lastConnectedAt: Date = .distantPast) {
        self.id = id
        self.name = name
        self.lastConnectedAt = lastConnectedAt
    }
}

protocol RememberedBandStoreProtocol: Sendable {
    func load() -> RememberedBand?
    func save(_ band: RememberedBand)
    func forget()
}

final class UserDefaultsRememberedBandStore: RememberedBandStoreProtocol, @unchecked Sendable {
    private enum Key {
        static let id = "rememberedBand.id"
        static let name = "rememberedBand.name"
        static let lastConnectedAt = "rememberedBand.lastConnectedAt"
    }
    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> RememberedBand? {
        lock.lock(); defer { lock.unlock() }
        guard let rawID = defaults.string(forKey: Key.id), let id = UUID(uuidString: rawID),
              let name = defaults.string(forKey: Key.name),
              let lastConnectedAt = defaults.object(forKey: Key.lastConnectedAt) as? Date else { return nil }
        return RememberedBand(id: id, name: name, lastConnectedAt: lastConnectedAt)
    }

    func save(_ band: RememberedBand) {
        lock.lock(); defer { lock.unlock() }
        defaults.set(band.id.uuidString, forKey: Key.id)
        defaults.set(band.name, forKey: Key.name)
        defaults.set(band.lastConnectedAt, forKey: Key.lastConnectedAt)
    }

    func forget() {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: Key.id)
        defaults.removeObject(forKey: Key.name)
        defaults.removeObject(forKey: Key.lastConnectedAt)
    }
}
