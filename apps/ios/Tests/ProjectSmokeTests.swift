import Foundation
import XCTest
@testable import BlueBandMap

final class ProjectSmokeTests: XCTestCase {
    func testIdentityConstantsAreStable() {
        XCTAssertEqual(BlueBandProduct.bundleIdentifier, "dev.lordierclaw.bluebandmap")
        XCTAssertEqual(BlueBandProduct.rpkPackage, "dev.lordierclaw.bluebandmap.band")
    }
}
