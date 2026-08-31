import Foundation

public enum VietmapStaticMapError: Swift.Error, Equatable {
    case invalidRequest
    case missingServiceKey
    case rateLimited
    case httpStatus(Int)
    case wrongContentType
}

public struct StaticMapRequest: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let zoom: Int
    public let width: Int
    public let height: Int

    public init(latitude: Double, longitude: Double, zoom: Int, width: Int, height: Int) {
        self.latitude = latitude
        self.longitude = longitude
        self.zoom = zoom
        self.width = width
        self.height = height
    }

    public init(
        validatingLatitude latitude: Double,
        longitude: Double,
        zoom: Int,
        width: Int,
        height: Int
    ) throws {
        guard (-90...90).contains(latitude),
              (-180...180).contains(longitude),
              (0...20).contains(zoom),
              [(212, 360), (159, 270)].contains(where: { $0 == (width, height) }) else {
            throw VietmapStaticMapError.invalidRequest
        }
        self.init(latitude: latitude, longitude: longitude, zoom: zoom, width: width, height: height)
    }
}

public protocol StaticMapProviding: Sendable {
    func fetch(_ request: StaticMapRequest, serviceKey: String) async throws -> MapAsset
}

public struct VietmapStaticMapClient: StaticMapProviding, Sendable {
    private let transport: any MapHTTPTransport
    private let boundary: String

    public init(transport: any MapHTTPTransport, boundary: String = "blueband-map-m1") {
        self.transport = transport
        self.boundary = boundary
    }

    public func fetch(_ request: StaticMapRequest, serviceKey: String) async throws -> MapAsset {
        _ = try StaticMapRequest(
            validatingLatitude: request.latitude,
            longitude: request.longitude,
            zoom: request.zoom,
            width: request.width,
            height: request.height
        )

        guard isValidBoundary else {
            throw VietmapStaticMapError.invalidRequest
        }

        let key = serviceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty,
              key.utf8.count <= 512,
              !key.utf8.contains(where: { $0 <= 31 || $0 == 127 }),
              !key.contains("--\(boundary)") else {
            throw VietmapStaticMapError.missingServiceKey
        }

        let fields = [
            ("lat", decimal(request.latitude)),
            ("lng", decimal(request.longitude)),
            ("apikey", key),
            ("zoom", String(request.zoom)),
            ("size", "\(request.width)x\(request.height)"),
        ]
        let httpRequest = MapHTTPRequest(
            method: "POST",
            url: URL(string: "https://maps.vietmap.vn/api/maps/statics/tm")!,
            headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"],
            body: multipart(fields),
            maximumResponseBytes: 64 * 1_024
        )

        let response = try await transport.execute(httpRequest)
        if response.statusCode == 429 {
            throw VietmapStaticMapError.rateLimited
        }
        guard response.statusCode == 200 else {
            throw VietmapStaticMapError.httpStatus(response.statusCode)
        }
        guard let contentType = response.header(named: "Content-Type") else {
            throw VietmapStaticMapError.wrongContentType
        }
        let mediaType = String(
            contentType.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)[0]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard mediaType.caseInsensitiveCompare("image/png") == .orderedSame else {
            throw VietmapStaticMapError.wrongContentType
        }
        return try MapAsset.png(
            data: response.body,
            expectedWidth: request.width,
            expectedHeight: request.height
        )
    }

    private func multipart(_ fields: [(String, String)]) -> Data {
        var body = ""
        for (name, value) in fields {
            body += "--\(boundary)\r\n"
            body += "Content-Disposition: form-data; name=\"\(name)\"\r\n"
            body += "\r\n"
            body += "\(value)\r\n"
        }
        body += "--\(boundary)--\r\n"
        return Data(body.utf8)
    }

    private func decimal(_ value: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private var isValidBoundary: Bool {
        (1...70).contains(boundary.utf8.count) && boundary.utf8.allSatisfy(Self.isTokenByte)
    }

    private static func isTokenByte(_ byte: UInt8) -> Bool {
        switch byte {
        case 48...57, 65...90, 97...122:
            true
        case 33, 35, 36, 37, 38, 39, 42, 43, 45, 46, 94, 95, 96, 124, 126:
            true
        default:
            false
        }
    }
}
