import Foundation
import XCTest
@testable import BlueBandMap

final class RememberedBandStoreTests: XCTestCase {
    func testSaveLoadAndForgetAreConfinedToOwnKeys() throws {
        let suite = "RememberedBandStoreTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("keep", forKey: "unrelated")
        let store = UserDefaultsRememberedBandStore(defaults: defaults)
        let connectedAt = Date(timeIntervalSince1970: 1_788_000_000)
        let band = RememberedBand(id: UUID(), name: "Xiaomi Smart Band 10", lastConnectedAt: connectedAt)

        store.save(band)
        XCTAssertEqual(store.load(), band)
        store.forget()
        XCTAssertNil(store.load())
        XCTAssertNil(defaults.object(forKey: "rememberedBand.id"))
        XCTAssertNil(defaults.object(forKey: "rememberedBand.name"))
        XCTAssertNil(defaults.object(forKey: "rememberedBand.lastConnectedAt"))
        XCTAssertEqual(defaults.string(forKey: "unrelated"), "keep")
    }

    func testLegacyRecordWithoutLastConnectedDateLoadsNil() throws {
        let suite = "RememberedBandStoreTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(UUID().uuidString, forKey: "rememberedBand.id")
        defaults.set("Legacy Band", forKey: "rememberedBand.name")

        let store = UserDefaultsRememberedBandStore(defaults: defaults)

        XCTAssertNil(store.load())
    }
}
