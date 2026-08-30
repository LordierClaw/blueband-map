import CoreBluetooth
import XCTest
@testable import BlueBandMap

final class BandUUIDTests: XCTestCase {
    func testUsesBand10XiaomiV2Endpoints() {
        XCTAssertEqual(BandUUID.service, CBUUID(string: "0000FE95-0000-1000-8000-00805F9B34FB"))
        XCTAssertEqual(BandUUID.notify, CBUUID(string: "0000005E-0000-1000-8000-00805F9B34FB"))
        XCTAssertEqual(BandUUID.write, CBUUID(string: "0000005F-0000-1000-8000-00805F9B34FB"))
        XCTAssertNil(BandDiscoveryPlan.scanServices)
    }

    func testFallbackNameDoesNotGateDiscovery() {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        XCTAssertEqual(BandDiscoveryPlan.displayName(peripheralName: nil, localName: "  ", id: id), "BLE AAAAAAAA")
    }
}
