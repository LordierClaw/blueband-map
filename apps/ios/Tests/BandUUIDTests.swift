import CoreBluetooth
import XCTest
@testable import BlueBandMap

final class BandUUIDTests: XCTestCase {
    func testUsesBand10XiaomiV2Endpoints() {
        XCTAssertEqual(BandUUID.service, CBUUID(string: "FE95"))
        XCTAssertEqual(BandUUID.notify, CBUUID(string: "5E"))
        XCTAssertEqual(BandUUID.write, CBUUID(string: "5F"))
        XCTAssertNil(BandDiscoveryPlan.scanServices)
    }

    func testFallbackNameDoesNotGateDiscovery() {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        XCTAssertEqual(BandDiscoveryPlan.displayName(peripheralName: nil, localName: "  ", id: id), "BLE AAAAAAAA")
    }
}
