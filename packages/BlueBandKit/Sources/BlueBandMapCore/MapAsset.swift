import Crypto
import Foundation

public struct MapAsset: Equatable, Sendable {
    public enum Error: Swift.Error, Equatable {
        case empty
        case tooLarge
        case wrongDimensions
    }

    public static let maximumPNGBytes = 200 * 1_024

    public let id: String
    public let mimeType: String
    public let width: Int
    public let height: Int
    public let data: Data
    public let sha256: String

    public var byteCount: Int { data.count }

    private init(id: String, mimeType: String, width: Int, height: Int, data: Data, sha256: String) {
        self.id = id
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.data = data
        self.sha256 = sha256
    }

    public static func png(data: Data, expectedWidth: Int, expectedHeight: Int) throws -> MapAsset {
        guard !data.isEmpty else {
            throw Error.empty
        }
        guard data.count <= maximumPNGBytes else {
            throw Error.tooLarge
        }

        let dimensions = try PNGInspector.dimensions(of: data)
        guard dimensions.width == expectedWidth, dimensions.height == expectedHeight else {
            throw Error.wrongDimensions
        }

        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return MapAsset(
            id: "m1-" + String(digest.prefix(16)),
            mimeType: "image/png",
            width: dimensions.width,
            height: dimensions.height,
            data: data,
            sha256: digest
        )
    }
}
