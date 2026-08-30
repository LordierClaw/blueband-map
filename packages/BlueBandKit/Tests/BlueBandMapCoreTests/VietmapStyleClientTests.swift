import Foundation
import XCTest
@testable import BlueBandMapCore

final class VietmapStyleClientTests: XCTestCase {
    private let key = "tile-test-key"

    func testDiscoversInlineVectorTilesAndRoadLayersWithAResponseCap() async throws {
        let style = """
        {
          "version": 8,
          "sources": {
            "vietmap": {
              "type": "vector",
              "tiles": ["https://maps.vietmap.vn/tiles/{z}/{x}/{y}.pbf?apikey={apikey}"]
            }
          },
          "layers": [
            {"id":"transportation","type":"line","source":"vietmap","source-layer":"road"},
            {"id":"water","type":"fill","source":"vietmap","source-layer":"water"}
          ]
        }
        """
        let transport = StyleRecordingTransport(responses: [jsonResponse(style)])
        let client = VietmapStyleClient(transport: transport)

        let template = try await client.discover(tileMapKey: key)

        XCTAssertEqual(template.urlTemplate, "https://maps.vietmap.vn/tiles/{z}/{x}/{y}.pbf?apikey={apikey}")
        XCTAssertEqual(template.sourceLayers, ["road"])
        let recordedRequests = await transport.requests()
        let request = try XCTUnwrap(recordedRequests.first)
        XCTAssertEqual(request.maximumResponseBytes, 2 * 1_024 * 1_024)
        XCTAssertTrue(request.url.absoluteString.contains("apikey=tile-test-key"))
    }

    func testResolvesOneTileJSONAndNeverIncludesKeyInErrors() async throws {
        let style = """
        {
          "version": 8,
          "sources": {
            "vietmap": {"type":"vector", "url":"https://maps.vietmap.vn/tiles.json?apikey={apikey}"}
          },
          "layers": [
            {"id":"road-casing","type":"line","source":"vietmap","source-layer":"transportation"}
          ]
        }
        """
        let tileJSON = "{" + "\"tiles\":[\"https://maps.vietmap.vn/vector/{z}/{x}/{y}.pbf?apikey={apikey}\"]" + "}"
        let transport = StyleRecordingTransport(responses: [jsonResponse(style), jsonResponse(tileJSON)])
        let template = try await VietmapStyleClient(transport: transport).discover(tileMapKey: key)

        XCTAssertEqual(template.urlTemplate, "https://maps.vietmap.vn/vector/{z}/{x}/{y}.pbf?apikey={apikey}")
        XCTAssertEqual(template.sourceLayers, ["transportation"])
        let recordedRequests = await transport.requests()
        XCTAssertEqual(recordedRequests.count, 2)
    }

    func testRejectsForeignHostsNonVectorSourcesAndMissingTiles() async {
        let foreignStyle = """
        {"version":8,"sources":{"vietmap":{"type":"vector","tiles":["https://evil.example/{z}/{x}/{y}.pbf"]}},"layers":[{"id":"road","type":"line","source":"vietmap","source-layer":"road"}]}
        """
        let nonVectorStyle = """
        {"version":8,"sources":{"vietmap":{"type":"raster","tiles":["https://maps.vietmap.vn/{z}/{x}/{y}.png"]}},"layers":[{"id":"road","type":"line","source":"vietmap","source-layer":"road"}]}
        """
        let missingTilesStyle = """
        {"version":8,"sources":{"vietmap":{"type":"vector"}},"layers":[{"id":"road","type":"line","source":"vietmap","source-layer":"road"}]}
        """

        for style in [foreignStyle, nonVectorStyle, missingTilesStyle] {
            let transport = StyleRecordingTransport(responses: [jsonResponse(style)])
            do {
                _ = try await VietmapStyleClient(transport: transport).discover(tileMapKey: key)
                XCTFail("Expected style rejection")
            } catch {
                XCTAssertFalse(String(describing: error).contains(key))
            }
        }
    }

    func testRejectsOversizedStyleBeforeParsing() async {
        let oversized = Data(repeating: 0x20, count: 2 * 1_024 * 1_024 + 1)
        let transport = StyleRecordingTransport(responses: [MapHTTPResponse(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: oversized
        )])
        do {
            _ = try await VietmapStyleClient(transport: transport).discover(tileMapKey: key)
            XCTFail("Expected response size rejection")
        } catch {
            XCTAssertEqual(error as? VietmapStyleError, .responseTooLarge)
        }
    }

    private func jsonResponse(_ string: String) -> MapHTTPResponse {
        MapHTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json; charset=utf-8"], body: Data(string.utf8))
    }
}

private actor StyleRecordingTransport: MapHTTPTransport {
    private var responseQueue: [MapHTTPResponse]
    private var recordedRequests: [MapHTTPRequest] = []

    init(responses: [MapHTTPResponse]) { responseQueue = responses }

    func execute(_ request: MapHTTPRequest) async throws -> MapHTTPResponse {
        recordedRequests.append(request)
        return responseQueue.removeFirst()
    }

    func requests() -> [MapHTTPRequest] { recordedRequests }
}
