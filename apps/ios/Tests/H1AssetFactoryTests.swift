import Foundation
import CoreGraphics
import ImageIO
import XCTest
import BlueBandMapCore
@testable import BlueBandMap

final class H1AssetFactoryTests: XCTestCase {
    private let key = "tile-test-key"

    func testOptimizedRasterRequestsReducedVietmapImageAndScalesItToTheBandViewport() async throws {
        let provider = H1RecordingStaticMapProvider()
        let factory = H1AssetFactory(staticMapProvider: provider)

        let asset = try await factory.make(
            mode: .rasterStaticCompact,
            serviceKey: "service-test-key",
            tileMapKey: nil
        )

        let requests = await provider.requests
        XCTAssertEqual(requests.map { [$0.width, $0.height] }, [[159, 270]])
        XCTAssertEqual(requests.map(\.zoom), [16])
        XCTAssertEqual(asset.kind, .raster)
        XCTAssertEqual(asset.width, RenderProtocol.viewportWidth)
        XCTAssertEqual(asset.height, RenderProtocol.viewportHeight)
    }

    func testVectorVietmapClampsZ17ToZ14AndAcceptsLegacyVietmapTile() async throws {
        let styleTransport = H1HTTPTransport(responses: [styleResponse(maximumZoom: 14)])
        let tileTransport = H1HTTPTransport(responses: [tileResponse(
            contentType: "text/plain; charset=utf-8",
            body: H1VectorTileFixture.centeredLineTile(y: 1_783)
        )])
        let factory = makeFactory(styleTransport: styleTransport, tileTransport: tileTransport)

        let asset = try await factory.make(mode: .vectorTileMap40, serviceKey: nil, tileMapKey: key)

        XCTAssertEqual(asset.kind, .vector)
        XCTAssertGreaterThan(asset.primitives, 0)
        let requests = await tileTransport.recordedRequests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url.path, "/mt/tile/data-20250529/14/13046/7699")
    }

    func testTileMapRasterUsesRealVectorTileGeometryAndProducesOnePNG() async throws {
        let asset = try await makeFactory(
            styleTransport: H1HTTPTransport(responses: [styleResponse(maximumZoom: 14)]),
            tileTransport: H1HTTPTransport(responses: [tileResponse(
                contentType: "application/x-protobuf",
                body: H1VectorTileFixture.centeredLineTile(y: 1_783)
            )])
        ).make(mode: .rasterTileMap, serviceKey: nil, tileMapKey: key)

        XCTAssertEqual(asset.kind, .raster)
        XCTAssertEqual(asset.primitives, 0)
        _ = try MapAsset.png(data: asset.data, expectedWidth: 212, expectedHeight: 360)
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
        ).make(mode: .vectorTileMap40, serviceKey: nil, tileMapKey: key)

        XCTAssertEqual(asset.kind, .vector)
    }

    func testVectorVietmapAcceptsMissingMIMEOnlyForValidatedVietmapPBF() async throws {
        let styleTransport = H1HTTPTransport(responses: [styleResponse(maximumZoom: 15)])
        let tileTransport = H1HTTPTransport(responses: [MapHTTPResponse(
            statusCode: 200,
            headers: [:],
            body: vietmapXOR(H1VectorTileFixture.centeredLineTile())
        )])

        let asset = try await makeFactory(
            styleTransport: styleTransport,
            tileTransport: tileTransport
        ).make(mode: .vectorTileMap40, serviceKey: nil, tileMapKey: key)

        XCTAssertEqual(asset.kind, .vector)
        XCTAssertGreaterThan(asset.primitives, 0)
    }

    func testTextPlainRequiresVietmapPBFPathAndValidMVTBody() async {
        let wrongPathStyle = styleResponse(maximumZoom: 15, pathExtension: "bin")
        let validBody = H1VectorTileFixture.centeredLineTile()
        let wrongPathFactory = makeFactory(
            styleTransport: H1HTTPTransport(responses: [wrongPathStyle]),
            tileTransport: H1HTTPTransport(responses: [tileResponse(contentType: "text/plain", body: validBody)])
        )
        do {
            _ = try await wrongPathFactory.make(mode: .vectorTileMap40, serviceKey: nil, tileMapKey: key)
            XCTFail("Expected text/plain on a non-PBF path to fail")
        } catch {
            XCTAssertEqual(error as? H1AssetFactory.Error, .tileWrongContentType)
        }

        let invalidBodyFactory = makeFactory(
            styleTransport: H1HTTPTransport(responses: [styleResponse(maximumZoom: 15)]),
            tileTransport: H1HTTPTransport(responses: [tileResponse(contentType: "text/plain", body: Data([0x1a, 0x80]))])
        )
        do {
            _ = try await invalidBodyFactory.make(mode: .vectorTileMap40, serviceKey: nil, tileMapKey: key)
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
            ).make(mode: .vectorTileMap40, serviceKey: nil, tileMapKey: key)
            XCTFail("Expected foreign tile host rejection")
        } catch {
            XCTAssertEqual(error as? VietmapStyleError, .invalidTileTemplate)
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
        {"version":8,"sources":{"vietmap":{"type":"vector","minzoom":0,"maxzoom":\(maximumZoom),"tiles":["https://maps.vietmap.vn/mt/tile/data-20250529/{z}/{x}/{y}\(pathExtension == "pbf" ? "" : ".\(pathExtension)")?apikey={apikey}"]}},"layers":[{"id":"road","type":"line","source":"vietmap","source-layer":"road"}]}
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
        MapHTTPResponse(
            statusCode: 200,
            headers: ["Content-Type": contentType],
            body: vietmapXOR(body)
        )
    }
}

private func vietmapXOR(_ data: Data) -> Data {
    let key: [UInt8] = [
        80, 88, 228, 30, 157, 170, 173, 154, 233, 247, 128, 170, 135, 27, 48, 165,
        148, 251, 99, 44, 105, 248, 18, 145, 34, 163, 70, 114, 228, 184, 229, 72,
    ]
    return Data(data.enumerated().map { index, byte in byte ^ key[index % key.count] })
}

private struct H1UnusedStaticMapProvider: StaticMapProviding {
    func fetch(_ request: StaticMapRequest, serviceKey: String) async throws -> MapAsset {
        throw VietmapStaticMapError.invalidRequest
    }
}

private actor H1RecordingStaticMapProvider: StaticMapProviding {
    private(set) var requests: [StaticMapRequest] = []

    func fetch(_ request: StaticMapRequest, serviceKey: String) async throws -> MapAsset {
        requests.append(request)
        return try MapAsset.png(
            data: h1PNG(width: request.width, height: request.height),
            expectedWidth: request.width,
            expectedHeight: request.height
        )
    }
}

private func h1PNG(width: Int, height: Int) throws -> Data {
    let pixels = Data(repeating: 0xCC, count: width * height * 4)
    guard let provider = CGDataProvider(data: pixels as CFData),
          let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
          ) else { throw IndexedPNGEncoder.Error.imageCreationFailed }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
        throw IndexedPNGEncoder.Error.destinationCreationFailed
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw IndexedPNGEncoder.Error.encodingFailed }
    return output as Data
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
    static func centeredLineTile(y: Int = 3_567) -> Data {
        let points = [(x: 0, y: y), (x: 4_095, y: y)]
        var value = Writer()
        value.string(field: 1, "primary")

        var feature = Writer()
        feature.varint(field: 1, 1)
        feature.bytes(field: 2, packedVarints([0, 0]))
        feature.varint(field: 3, 2)
        feature.bytes(field: 4, geometry(points))

        var layer = Writer()
        layer.string(field: 1, "road")
        layer.bytes(field: 2, feature.data)
        layer.string(field: 3, "class")
        layer.bytes(field: 4, value.data)
        layer.varint(field: 5, 4_096)
        layer.varint(field: 15, 2)

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
