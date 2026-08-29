import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public struct ApplicationEnvelope: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable { case ios, band }
    public enum MessageType: String, Codable, Sendable { case message, ack }
    public enum Error: Swift.Error, Equatable {
        case tooLarge
        case unsupportedVersion
        case invalidIdentifier
        case unexpectedSource
        case invalidTopic
        case invalidMessageShape
        case invalidAcknowledgementShape
    }

    public static let version = 1
    public static let maximumEncodedSize = 512

    public let v: Int
    public let id: String
    public let src: Source
    public let type: MessageType
    public let topic: String?
    public let body: [String: JSONValue]?

    public init(v: Int, id: String, src: Source, type: MessageType, topic: String?, body: [String: JSONValue]?) {
        self.v = v
        self.id = id
        self.src = src
        self.type = type
        self.topic = topic
        self.body = body
    }

    public static func message(id: String, source: Source, topic: String, body: [String: JSONValue]) -> Self {
        Self(v: version, id: id, src: source, type: .message, topic: topic, body: body)
    }

    public static func acknowledgement(id: String, source: Source) -> Self {
        Self(v: version, id: id, src: source, type: .ack, topic: nil, body: nil)
    }

    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumEncodedSize else { throw Error.tooLarge }
        return data
    }

    public static func decode(_ data: Data, expecting localSource: Source) throws -> Self {
        guard data.count <= maximumEncodedSize else { throw Error.tooLarge }
        let envelope = try JSONDecoder().decode(Self.self, from: data)
        try envelope.validate()
        guard envelope.src != localSource else { throw Error.unexpectedSource }
        return envelope
    }

    private func validate() throws {
        guard v == Self.version else { throw Error.unsupportedVersion }
        let identifierBytes = id.utf8
        guard (1...32).contains(identifierBytes.count), identifierBytes.allSatisfy({ (0x20...0x7E).contains($0) }) else {
            throw Error.invalidIdentifier
        }

        switch type {
        case .message:
            guard let topic, body != nil else { throw Error.invalidMessageShape }
            let bytes = topic.utf8
            guard (1...64).contains(bytes.count), isValidTopic(topic) else { throw Error.invalidTopic }
        case .ack:
            guard topic == nil, body == nil else { throw Error.invalidAcknowledgementShape }
        }
    }

    private func isValidTopic(_ topic: String) -> Bool {
        let segments = topic.split(separator: ".", omittingEmptySubsequences: false)
        guard !segments.isEmpty else { return false }
        return segments.allSatisfy { segment in
            !segment.isEmpty && segment.utf8.allSatisfy { byte in
                (0x61...0x7A).contains(byte) || (0x30...0x39).contains(byte) || byte == 0x2D
            }
        }
    }
}
