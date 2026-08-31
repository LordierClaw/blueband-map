import Foundation
import XCTest
@testable import BlueBandMapCore

final class HTTPTransportTests: XCTestCase {
    func testRequestAndResponsePreserveOnlyExplicitHTTPFields() async throws {
        let request = MapHTTPRequest(
            method: "POST",
            url: try XCTUnwrap(URL(string: "https://maps.vietmap.vn/api/maps/statics/tm")),
            headers: ["Content-Type": "multipart/form-data; boundary=blueband"],
            body: Data("body".utf8)
        )
        let transport = RecordingHTTPTransport(
            response: MapHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data([1, 2]))
        )

        let response = try await transport.execute(request)
        let lastRequest = await transport.lastRequest()

        XCTAssertEqual(lastRequest, request)
        XCTAssertEqual(lastRequest?.maximumResponseBytes, 256 * 1_024)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.header(named: "Content-Type"), "image/png")
    }
}

private actor RecordingHTTPTransport: MapHTTPTransport {
    private let response: MapHTTPResponse
    private var request: MapHTTPRequest?

    init(response: MapHTTPResponse) { self.response = response }

    func execute(_ request: MapHTTPRequest) async throws -> MapHTTPResponse {
        self.request = request
        return response
    }

    func lastRequest() -> MapHTTPRequest? { request }
}
