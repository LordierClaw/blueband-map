import XCTest
@testable import BlueBandProtocol

final class BlueBandIdentityTests: XCTestCase {
    func testExpectedRPKPackageRoutesTheBandApplication() {
        XCTAssertEqual(BlueBandIdentity.rpkPackage, "dev.lordierclaw.bluebandmap.band")
        XCTAssertEqual(BlueBandIdentity.envelopeVersion, 1)
    }
}
