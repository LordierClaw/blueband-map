import Foundation
import XCTest
import BlueBandMapCore
@testable import BlueBandMap

final class H1AssetFactoryTests: XCTestCase {
    private let key = "tile-test-key"

    func testVectorVietmapClampsZ17ToZ15AndAcceptsVietmapTextPlainPBF() async throws {
        let styleTransport = H1HTTPTransport(responses: [styleResponse(maximumZoom: 15)])
        let tileTransport = H1HTTPTransport(responses: [tileResponse(
            contentType: "text/plain; charset=utf-8",
            body: H1VectorTileFixture.centeredLineTile()
        )])
        let factory = makeFactory(styleTransport: styleTransport, tileTransport: tileTransport)

        let asset = try await factory.make(mode: .vectorVietmap, serviceKey: nil, tileMapKey: key)

        XCTAssertEqual(asset.kind, .vector)
        XCTAssertGreaterThan(asset.primitives, 0)
        let requests = await tileTransport.recordedRequests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url.path, "/maps/tiles/vlc-20260824/15/26093/15398.pbf")
    }

    func testVectorVietmapKeepsExistingVectorMIMEType() async throws {
        let styleTransport = H1HTTPTransport(responses: [styleResponse(maximumZoom: 15)])
        let tileTransport = H1HTTPTransport(responses: [tileResponse(
            contentType: "application/x-protobuf",
            body: H1VectorTileFixture.centeredLineTile()
        )])

        let asset = try await makeFactory(
            styleTransport: styleTransport,
            tileTransport: tileTransport
        ).make(mode: .vectorVietmap, serviceKey: nil, tileMapKey: key)

        XCTAssertEqual(asset.kind, .vector)
    }

    func testTextPlainRequiresVietmapPBFPathAndValidMVTBody() async {
        let wrongPathStyle = styleResponse(maximumZoom: 15, pathExtension: "bin")
        let validBody = H1VectorTileFixture.centeredLineTile()
        let wrongPathFactory = makeFactory(
            styleTransport: H1HTTPTransport(responses: [wrongPathStyle]),
            tileTransport: H1HTTPTransport(responses: [tileResponse(contentType: "text/plain", body: validBody)])
        )
        do {
            _ = try await wrongPathFactory.make(mode: .vectorVietmap, serviceKey: nil, tileMapKey: key)
            XCTFail("Expected text/plain on a non-PBF path to fail")
        } catch {
            XCTAssertEqual(error as? H1AssetFactory.Error, .tileWrongContentType)
        }

        let invalidBodyFactory = makeFactory(
            styleTransport: H1HTTPTransport(responses: [styleResponse(maximumZoom: 15)]),
            tileTransport: H1HTTPTransport(responses: [tileResponse(contentType: "text/plain", body: Data([0x1a, 0x80]))])
        )
        do {
            _ = try await invalidBodyFactory.make(mode: .vectorVietmap, serviceKey: nil, tileMapKey: key)
            XCTFail("Expected invalid MVT data to fail")
        } catch {
            XCTAssertEqual(error as? MapboxVectorTile.Error, .truncated)
        }
    }

    func testForeignTileHostIsRejectedBeforeTextPlainCanBeAccepted() async {
        let foreignStyle = """
        {"version":8,"sources":{"vietmap":{"type":"vector","maxzoom":15,"tiles":["https://evil.example/maps/{z}/{x}/{y}.pbf?apikey={apikey}"]}},"layers":[{"id":"road","type":"line","source":"vietmap","source-layer":"road"}]}
        """
        let styleTransport = H1HTTPTransport(responses: [jsonResponse(foreignStyle)])
        let tileTransport = H1HTTPTransport(responses: [tileResponse(
            contentType: "text/plain",
            body: H1VectorTileFixture.centeredLineTile()
        )])

        do {
            _ = try await makeFactory(
                styleTransport: styleTransport,
                tileTransport: tileTransport
            ).make(mode: .vectorVietmap, serviceKey: nil, tileMapKey: key)
            XCTFail("Expected foreign tile host rejection")
        } catch {
            XCTAssertEqual(error as? VietmapStyleError, .foreignHost)
            let requests = await tileTransport.recordedRequests
            XCTAssertTrue(requests.isEmpty)
        }
    }

    private func makeFactory(
        styleTransport: H1HTTPTransport,
        tileTransport: H1HTTPTransport
    ) -> H1AssetFactory {
        H1AssetFactory(
            staticMapProvider: H1UnusedStaticMapProvider(),
            styleClient: VietmapStyleClient(transport: styleTransport),
            tileTransport: tileTransport
        )
    }

    private func styleResponse(maximumZoom: Int, pathExtension: String = "pbf") -> MapHTTPResponse {
        jsonResponse("""
        {"version":8,"sources":{"vietmap":{"type":"vector","minzoom":0,"maxzoom":\(maximumZoom),"tiles":["https://maps.vietmap.vn/maps/tiles/vlc-20260824/{z}/{x}/{y}.\(pathExtension)?apikey={apikey}"]}},"layers":[{"id":"road","type":"line","source":"vietmap","source-layer":"road"}]}
        """)
    }

    private func jsonResponse(_ string: String) -> MapHTTPResponse {
        MapHTTPResponse(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(string.utf8)
        )
    }

    private func tileResponse(contentType: String, body: Data) -> MapHTTPResponse {
        MapHTTPResponse(statusCode: 200, headers: ["Content-Type": contentType], body: body)
    }
}

private struct H1UnusedStaticMapProvider: StaticMapProviding {
    func fetch(_ request: StaticMapRequest, serviceKey: String) async throws -> MapAsset {
        throw VietmapStaticMapError.invalidRequest
    }
}

private actor H1HTTPTransport: MapHTTPTransport {
    private var responses: [MapHTTPResponse]
    private(set) var recordedRequests: [MapHTTPRequest] = []

    init(responses: [MapHTTPResponse]) {
        self.responses = responses
    }

    func execute(_ request: MapHTTPRequest) async throws -> MapHTTPResponse {
        recordedRequests.append(request)
        return responses.removeFirst()
    }
}

private enum H1VectorTileFixture {
    static func centeredLineTile() -> Data {
        let points = [(x: 0, y: 3_567), (x: 4_095, y: 3_567)]
        var value = Writer()
        value.string(field: 1, "primary")

        var feature = Writer()
        feature.varint(field: 1, 1)
        feature.bytes(field: 2, packedVarints([0, 0]))
        feature.varint(field: 3, 2)
        feature.bytes(field: 4, geometry(points))

        var layer = Writer()
        layer.varint(field: 1, 2)
        layer.string(field: 2, "road")
        layer.bytes(field: 3, feature.data)
        layer.string(field: 4, "class")
        layer.bytes(field: 5, value.data)
        layer.varint(field: 15, 4_096)

        var tile = Writer()
        tile.bytes(field: 3, layer.data)
        return tile.data
    }

    private static func geometry(_ points: [(x: Int, y: Int)]) -> Data {
        guard let first = points.first else { return Data() }
        var values = [UInt64((1 << 3) | 1), zigZag(first.x), zigZag(first.y)]
        var previous = first
        values.append((UInt64(points.count - 1) << 3) | 2)
        for point in points.dropFirst() {
            values.append(zigZag(point.x - previous.x))
            values.append(zigZag(point.y - previous.y))
            previous = point
        }
        return packedVarints(values)
    }

    private static func zigZag(_ value: Int) -> UInt64 {
        UInt64(bitPattern: Int64(value << 1 ^ value >> 63))
    }

    private static func packedVarints(_ values: [UInt64]) -> Data {
        var writer = Writer()
        for value in values { writer.rawVarint(value) }
        return writer.data
    }

    private struct Writer {
        var data = Data()

        mutating func varint(field: Int, _ value: UInt64) {
            rawVarint(UInt64(field) << 3)
            rawVarint(value)
        }

        mutating func string(field: Int, _ value: String) {
            bytes(field: field, Data(value.utf8))
        }

        mutating func bytes(field: Int, _ value: Data) {
            rawVarint((UInt64(field) << 3) | 2)
            rawVarint(UInt64(value.count))
            data.append(value)
        }

        mutating func rawVarint(_ value: UInt64) {
            var remaining = value
            while remaining >= 0x80 {
                data.append(UInt8(truncatingIfNeeded: remaining) | 0x80)
                remaining >>= 7
            }
            data.append(UInt8(remaining))
        }
    }
}
