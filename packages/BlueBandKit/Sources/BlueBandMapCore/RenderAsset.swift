import Crypto
import Foundation

public struct RenderAsset: Equatable, Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case empty
        case tooLarge
        case invalidDimensions
        case unsupportedFormatVersion
        case invalidFormat
        case tooManyPrimitives
    }

    public let id: String
    public let kind: RenderKind
    public let format: RenderFormat
    public let formatVersion: Int
    public let width: Int
    public let height: Int
    public let data: Data
    public let sha256: String
    public let primitives: Int

    public var byteCount: Int { data.count }

    public init(
        kind: RenderKind,
        format: RenderFormat = .png,
        formatVersion: Int,
        width: Int,
        height: Int,
        data: Data,
        primitives: Int
    ) throws {
        guard width == RenderProtocol.viewportWidth, height == RenderProtocol.viewportHeight else {
            throw Error.invalidDimensions
        }
        guard formatVersion == RenderProtocol.formatVersion else {
            throw Error.unsupportedFormatVersion
        }
        guard !data.isEmpty else { throw Error.empty }
        guard data.count <= RenderProtocol.maximumPayloadBytes else { throw Error.tooLarge }
        guard (0...RenderProtocol.maximumPrimitives).contains(primitives) else {
            throw Error.tooManyPrimitives
        }

        self.kind = kind
        self.format = format
        self.formatVersion = formatVersion
        self.width = width
        self.height = height
        self.data = data
        self.sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        self.id = "nav-" + String(self.sha256.prefix(16))
        self.primitives = primitives
    }
}
