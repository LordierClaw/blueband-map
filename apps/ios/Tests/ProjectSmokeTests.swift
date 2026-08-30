import Foundation
import XCTest
@testable import BlueBandMap

final class ProjectSmokeTests: XCTestCase {
    func testIdentityConstantsAreStable() {
        XCTAssertEqual(BlueBandProduct.bundleIdentifier, "dev.lordierclaw.bluebandmap")
        XCTAssertEqual(BlueBandProduct.rpkPackage, "dev.lordierclaw.bluebandmap.band")
        XCTAssertEqual(BlueBandProduct.version, "0.1.3")
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

    func testH1ExposesIndependentRasterAndVectorModes() {
        let stateSource = try! String(contentsOf: sourceRoot.appendingPathComponent("App/H1State.swift"))
        let modelSource = try! String(contentsOf: sourceRoot.appendingPathComponent("App/AppModel.swift"))
        let viewSource = try! String(contentsOf: sourceRoot.appendingPathComponent("App/ContentView.swift"))
        let factorySource = try! String(contentsOf: sourceRoot.appendingPathComponent("Adapters/Rendering/H1AssetFactory.swift"))

        XCTAssertTrue(stateSource.contains("case rasterBaseline"))
        XCTAssertTrue(stateSource.contains("case vectorVietmap"))
        XCTAssertTrue(modelSource.contains("func startH1(mode: H1TestMode) async"))
        XCTAssertTrue(viewSource.contains("ForEach(H1TestMode.allCases"))
        XCTAssertTrue(factorySource.contains("VietmapStyleClient"))
        XCTAssertTrue(factorySource.contains("MapboxVectorTile.decode"))
    }

    func testH1ExportUsesFileTransferRepresentationForTheExistingSanitizedFile() {
        let modelSource = try! String(contentsOf: sourceRoot.appendingPathComponent("App/AppModel.swift"))
        let viewSource = try! String(contentsOf: sourceRoot.appendingPathComponent("App/ContentView.swift"))
        let exportSource = try! String(contentsOf: sourceRoot.appendingPathComponent("App/H1LogExport.swift"))

        XCTAssertTrue(viewSource.contains("ShareLink(\"Export log H1\", item: H1LogExport(url: export))"))
        XCTAssertTrue(viewSource.contains("if let export = model.lastH1ExportURL"))
        XCTAssertTrue(exportSource.contains("FileRepresentation(contentType: .json)"))
        XCTAssertTrue(exportSource.contains("SentTransferredFile(export.url)"))
        XCTAssertFalse(viewSource.contains("model.exportLastH1Run()"))
        XCTAssertFalse(modelSource.contains("func exportLastH1Run()"))
    }

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }
}
