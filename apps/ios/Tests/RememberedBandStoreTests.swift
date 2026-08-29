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
        let band = RememberedBand(id: UUID(), name: "Xiaomi Smart Band 10")

        store.save(band)
        XCTAssertEqual(store.load(), band)
        store.forget()
        XCTAssertNil(store.load())
        XCTAssertEqual(defaults.string(forKey: "unrelated"), "keep")
    }
}
