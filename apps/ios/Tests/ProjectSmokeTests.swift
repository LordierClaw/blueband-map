import Foundation
import XCTest
@testable import BlueBandMap

final class ProjectSmokeTests: XCTestCase {
    func testIdentityConstantsAreStable() {
        XCTAssertEqual(BlueBandProduct.bundleIdentifier, "dev.lordierclaw.bluebandmap")
        XCTAssertEqual(BlueBandProduct.rpkPackage, "dev.lordierclaw.bluebandmap.band")
    }

    func testM1StateHasOnlyTheApprovedCases() {
        let source = try! String(contentsOf: sourceRoot.appendingPathComponent("App/M1State.swift"))
        for declaration in [
            "case idle",
            "case fetching",
            "case transferring(completed: Int, total: Int)",
            "case waitingForBand(assetID: String, hashPrefix: String)",
            "case displayed(assetID: String, hashPrefix: String)",
            "case failed(code: String)",
        ] {
            XCTAssertTrue(source.contains(declaration), "Missing \(declaration)")
        }
    }

    func testM1UsesOneDocumentedStaticMapRequest() {
        XCTAssertEqual(M1Configuration.request.latitude, 10.759157, accuracy: 0.000001)
        XCTAssertEqual(M1Configuration.request.longitude, 106.675859, accuracy: 0.000001)
        XCTAssertEqual(M1Configuration.request.zoom, 17)
        XCTAssertEqual(M1Configuration.request.width, 212)
        XCTAssertEqual(M1Configuration.request.height, 360)
        XCTAssertEqual(M1Configuration.maximumProviderCalls, 1)
    }

    func testAppDoesNotAutomaticallyStartM1() {
        let source = try! String(contentsOf: sourceRoot.appendingPathComponent("App/AppModel.swift"))
        XCTAssertEqual(source.components(separatedBy: "startM1()").count - 1, 1)
    }

    func testM1ReconnectGateIsVisibleAndDisablesRetry() {
        let modelSource = try! String(contentsOf: sourceRoot.appendingPathComponent("App/AppModel.swift"))
        let viewSource = try! String(contentsOf: sourceRoot.appendingPathComponent("App/ContentView.swift"))
        XCTAssertTrue(modelSource.contains("TRANSFER_RECONNECT_REQUIRED"))
        XCTAssertTrue(modelSource.contains("m1ReconnectObservedDisconnect"))
        XCTAssertTrue(viewSource.contains("model.m1RequiresReconnect"))
        XCTAssertTrue(viewSource.contains("Cần ngắt kết nối và kết nối lại Band"))
    }

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }
}
