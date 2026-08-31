import Foundation
import XCTest
@testable import BlueBandMapCore

final class VietmapStaticMapClientTests: XCTestCase {
    func testBuildsExactDocumentedMultipartPOSTAndReturnsValidatedPNG() async throws {
        let png = makePNG(width: 212, height: 360)
        let transport = QueueHTTPTransport(responses: [
            MapHTTPResponse(statusCode: 200, headers: ["Content-Type": "image/png"], body: png),
        ])
        let client = VietmapStaticMapClient(transport: transport, boundary: "blueband-boundary")
        let request = validRequest()

        let asset = try await client.fetch(request, serviceKey: "service-test-key")
        let recordedRequests = await transport.requests()
        let sent = try XCTUnwrap(recordedRequests.first)
        let expectedBody = """
        --blueband-boundary\r
        Content-Disposition: form-data; name="lat"\r
        \r
        10.759157\r
        --blueband-boundary\r
        Content-Disposition: form-data; name="lng"\r
        \r
        106.675859\r
        --blueband-boundary\r
        Content-Disposition: form-data; name="apikey"\r
        \r
        service-test-key\r
        --blueband-boundary\r
        Content-Disposition: form-data; name="zoom"\r
        \r
        17\r
        --blueband-boundary\r
        Content-Disposition: form-data; name="size"\r
        \r
        212x360\r
        --blueband-boundary--\r

        """

        XCTAssertEqual(recordedRequests.count, 1)
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.url.absoluteString, "https://maps.vietmap.vn/api/maps/statics/tm")
        XCTAssertEqual(sent.headers, ["Content-Type": "multipart/form-data; boundary=blueband-boundary"])
        XCTAssertEqual(sent.maximumResponseBytes, 64 * 1_024)
        XCTAssertEqual(String(decoding: sent.body, as: UTF8.self), expectedBody)
        XCTAssertEqual(asset.data, png)
        XCTAssertEqual(asset.mimeType, "image/png")
        XCTAssertEqual(asset.width, 212)
        XCTAssertEqual(asset.height, 360)
    }

    func testTrimsServiceKeyBeforeBuildingBody() async throws {
        let transport = successfulTransport()
        let client = VietmapStaticMapClient(transport: transport, boundary: "b")

        _ = try await client.fetch(validRequest(), serviceKey: " \tservice-test-key\r\n")

        let recordedRequests = await transport.requests()
        let sent = try XCTUnwrap(recordedRequests.first)
        let body = String(decoding: sent.body, as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"apikey\"\r\n\r\nservice-test-key\r\n"))
        XCTAssertFalse(body.contains(" \tservice-test-key"))
    }

    func testRejectsInvalidMultipartBoundariesWithoutExecutingTransport() async {
        let invalidBoundaries = [
            "",
            "blue\rband",
            "blue\nband",
            "blue\"band",
            "blue band",
            "blue/band",
            "blue;band",
            "blue[band",
            "blue💙band",
            String(repeating: "b", count: 71),
        ]

        for boundary in invalidBoundaries {
            let transport = QueueHTTPTransport(responses: [])
            let client = VietmapStaticMapClient(transport: transport, boundary: boundary)

            await XCTAssertThrowsErrorAsync(
                try await client.fetch(validRequest(), serviceKey: "service-test-key")
            ) { error in
                XCTAssertEqual(error as? VietmapStaticMapError, .invalidRequest)
            }
            let requestCount = await transport.requests().count
            XCTAssertEqual(requestCount, 0)
        }
    }

    func testRejectsEmptyAndWhitespaceServiceKeysWithoutExecutingTransport() async {
        for serviceKey in ["", "   \t\r\n"] {
            let transport = QueueHTTPTransport(responses: [])
            let client = VietmapStaticMapClient(transport: transport)

            await XCTAssertThrowsErrorAsync(
                try await client.fetch(validRequest(), serviceKey: serviceKey)
            ) { error in
                XCTAssertEqual(error as? VietmapStaticMapError, .missingServiceKey)
            }
            let requestCount = await transport.requests().count
            XCTAssertEqual(requestCount, 0)
        }
    }

    func testRejectsServiceKeyAbove512UTF8BytesWithoutExecutingTransport() async {
        let transport = QueueHTTPTransport(responses: [])
        let client = VietmapStaticMapClient(transport: transport)
        let serviceKey = String(repeating: "é", count: 257)
        XCTAssertEqual(serviceKey.utf8.count, 514)

        await XCTAssertThrowsErrorAsync(
            try await client.fetch(validRequest(), serviceKey: serviceKey)
        ) { error in
            XCTAssertEqual(error as? VietmapStaticMapError, .missingServiceKey)
        }
        let requestCount = await transport.requests().count
        XCTAssertEqual(requestCount, 0)
    }

    func testRejectsServiceKeysContainingASCIIControlsWithoutExecutingTransport() async {
        let invalidServiceKeys = [
            "service\r\nInjected: value",
            "service\u{0000}key",
            "service\u{001f}key",
            "service\u{007f}key",
        ]

        for serviceKey in invalidServiceKeys {
            let transport = QueueHTTPTransport(responses: [])
            let client = VietmapStaticMapClient(transport: transport, boundary: "blueband-boundary")

            await XCTAssertThrowsErrorAsync(
                try await client.fetch(validRequest(), serviceKey: serviceKey)
            ) { error in
                XCTAssertEqual(error as? VietmapStaticMapError, .missingServiceKey)
            }
            let requestCount = await transport.requests().count
            XCTAssertEqual(requestCount, 0)
        }
    }

    func testRejectsServiceKeyContainingActiveDelimiterWithoutExecutingTransport() async {
        let transport = QueueHTTPTransport(responses: [])
        let client = VietmapStaticMapClient(transport: transport, boundary: "blueband-boundary")

        await XCTAssertThrowsErrorAsync(
            try await client.fetch(
                validRequest(),
                serviceKey: "service--blueband-boundaryinjected"
            )
        ) { error in
            XCTAssertEqual(error as? VietmapStaticMapError, .missingServiceKey)
        }
        let requestCount = await transport.requests().count
        XCTAssertEqual(requestCount, 0)
    }

    func testMapsHTTP429ToRateLimited() async {
        let transport = QueueHTTPTransport(responses: [
            MapHTTPResponse(statusCode: 429, headers: [:], body: Data()),
        ])
        let client = VietmapStaticMapClient(transport: transport)

        await XCTAssertThrowsErrorAsync(
            try await client.fetch(validRequest(), serviceKey: "service-test-key")
        ) { error in
            XCTAssertEqual(error as? VietmapStaticMapError, .rateLimited)
        }
        let requestCount = await transport.requests().count
        XCTAssertEqual(requestCount, 1)
    }

    func testMapsOtherNon200StatusToHTTPStatus() async {
        let transport = QueueHTTPTransport(responses: [
            MapHTTPResponse(statusCode: 503, headers: ["Content-Type": "image/png"], body: Data()),
        ])
        let client = VietmapStaticMapClient(transport: transport)

        await XCTAssertThrowsErrorAsync(
            try await client.fetch(validRequest(), serviceKey: "service-test-key")
        ) { error in
            XCTAssertEqual(error as? VietmapStaticMapError, .httpStatus(503))
        }
        let requestCount = await transport.requests().count
        XCTAssertEqual(requestCount, 1)
    }

    func testRejectsMissingOrWrongContentType() async {
        for headers in [[:], ["Content-Type": "application/octet-stream"]] {
            let transport = QueueHTTPTransport(responses: [
                MapHTTPResponse(statusCode: 200, headers: headers, body: makePNG(width: 212, height: 360)),
            ])
            let client = VietmapStaticMapClient(transport: transport)

            await XCTAssertThrowsErrorAsync(
                try await client.fetch(validRequest(), serviceKey: "service-test-key")
            ) { error in
                XCTAssertEqual(error as? VietmapStaticMapError, .wrongContentType)
            }
            let requestCount = await transport.requests().count
            XCTAssertEqual(requestCount, 1)
        }
    }

    func testRejectsContentTypesWithImagePNGPrefixOnly() async {
        for contentType in ["image/png-malware", "image/pngfoo", "image/png+custom"] {
            let transport = QueueHTTPTransport(responses: [
                MapHTTPResponse(
                    statusCode: 200,
                    headers: ["Content-Type": contentType],
                    body: makePNG(width: 212, height: 360)
                ),
            ])
            let client = VietmapStaticMapClient(transport: transport)

            await XCTAssertThrowsErrorAsync(
                try await client.fetch(validRequest(), serviceKey: "service-test-key")
            ) { error in
                XCTAssertEqual(error as? VietmapStaticMapError, .wrongContentType)
            }
            let requestCount = await transport.requests().count
            XCTAssertEqual(requestCount, 1)
        }
    }

    func testAcceptsImagePNGContentTypeCaseInsensitivelyWithParameters() async throws {
        let png = makePNG(width: 212, height: 360)
        let transport = QueueHTTPTransport(responses: [
            MapHTTPResponse(
                statusCode: 200,
                headers: ["cOnTeNt-TyPe": " \tImAgE/PnG\r\n ; charset=binary"],
                body: png
            ),
        ])
        let client = VietmapStaticMapClient(transport: transport)

        let asset = try await client.fetch(validRequest(), serviceKey: "service-test-key")

        XCTAssertEqual(asset.data, png)
        let requestCount = await transport.requests().count
        XCTAssertEqual(requestCount, 1)
    }

    func testValidatingInitializerRejectsOutOfRangeCoordinatesZoomAndDimensions() {
        let invalidRequests: [(Double, Double, Int, Int, Int)] = [
            (-90.000001, 106.675859, 17, 212, 360),
            (90.000001, 106.675859, 17, 212, 360),
            (10.759157, -180.000001, 17, 212, 360),
            (10.759157, 180.000001, 17, 212, 360),
            (10.759157, 106.675859, -1, 212, 360),
            (10.759157, 106.675859, 21, 212, 360),
            (10.759157, 106.675859, 17, 211, 360),
            (10.759157, 106.675859, 17, 212, 359),
        ]

        for (latitude, longitude, zoom, width, height) in invalidRequests {
            XCTAssertThrowsError(
                try StaticMapRequest(
                    validatingLatitude: latitude,
                    longitude: longitude,
                    zoom: zoom,
                    width: width,
                    height: height
                )
            ) { error in
                XCTAssertEqual(error as? VietmapStaticMapError, .invalidRequest)
            }
        }
    }

    func testAcceptsTheReducedH1StaticMapSize() throws {
        let request = try StaticMapRequest(
            validatingLatitude: 10.759157,
            longitude: 106.675859,
            zoom: 17,
            width: 159,
            height: 270
        )

        XCTAssertEqual(request.width, 159)
        XCTAssertEqual(request.height, 270)
    }

    func testFetchRevalidatesRequestCreatedWithNonthrowingInitializer() async {
        let transport = QueueHTTPTransport(responses: [])
        let client = VietmapStaticMapClient(transport: transport)
        let invalidRequest = StaticMapRequest(
            latitude: 91,
            longitude: 106.675859,
            zoom: 17,
            width: 212,
            height: 360
        )

        await XCTAssertThrowsErrorAsync(
            try await client.fetch(invalidRequest, serviceKey: "service-test-key")
        ) { error in
            XCTAssertEqual(error as? VietmapStaticMapError, .invalidRequest)
        }
        let requestCount = await transport.requests().count
        XCTAssertEqual(requestCount, 0)
    }

    func testFetchRejectsNonFiniteCoordinatesWithoutExecutingTransport() async {
        let coordinates: [(Double, Double)] = [
            (.nan, 106.675859),
            (.infinity, 106.675859),
            (-.infinity, 106.675859),
            (10.759157, .nan),
            (10.759157, .infinity),
            (10.759157, -.infinity),
        ]

        for (latitude, longitude) in coordinates {
            let transport = QueueHTTPTransport(responses: [])
            let client = VietmapStaticMapClient(transport: transport)
            let request = StaticMapRequest(
                latitude: latitude,
                longitude: longitude,
                zoom: 17,
                width: 212,
                height: 360
            )

            await XCTAssertThrowsErrorAsync(
                try await client.fetch(request, serviceKey: "service-test-key")
            ) { error in
                XCTAssertEqual(error as? VietmapStaticMapError, .invalidRequest)
            }
            let requestCount = await transport.requests().count
            XCTAssertEqual(requestCount, 0)
        }
    }
}

private enum QueueHTTPTransportError: Swift.Error {
    case missingResponse
}

private actor QueueHTTPTransport: MapHTTPTransport {
    private var queuedResponses: [MapHTTPResponse]
    private var recordedRequests: [MapHTTPRequest] = []

    init(responses: [MapHTTPResponse]) {
        queuedResponses = responses
    }

    func execute(_ request: MapHTTPRequest) async throws -> MapHTTPResponse {
        recordedRequests.append(request)
        guard !queuedResponses.isEmpty else {
            throw QueueHTTPTransportError.missingResponse
        }
        return queuedResponses.removeFirst()
    }

    func requests() -> [MapHTTPRequest] {
        recordedRequests
    }
}

private func validRequest() -> StaticMapRequest {
    StaticMapRequest(
        latitude: 10.759157,
        longitude: 106.675859,
        zoom: 17,
        width: 212,
        height: 360
    )
}

private func successfulTransport() -> QueueHTTPTransport {
    QueueHTTPTransport(responses: [
        MapHTTPResponse(
            statusCode: 200,
            headers: ["Content-Type": "image/png"],
            body: makePNG(width: 212, height: 360)
        ),
    ])
}

private func makePNG(width: UInt32, height: UInt32) -> Data {
    var bytes: [UInt8] = [
        137, 80, 78, 71, 13, 10, 26, 10,
        0, 0, 0, 13,
        73, 72, 68, 82,
    ]
    bytes.append(contentsOf: bigEndianBytes(width))
    bytes.append(contentsOf: bigEndianBytes(height))
    bytes.append(contentsOf: [8, 6, 0, 0, 0])
    return Data(bytes)
}

private func bigEndianBytes(_ value: UInt32) -> [UInt8] {
    [
        UInt8((value >> 24) & 0xff),
        UInt8((value >> 16) & 0xff),
        UInt8((value >> 8) & 0xff),
        UInt8(value & 0xff),
    ]
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ verify: (Swift.Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error")
    } catch {
        verify(error)
    }
}
