import Foundation

public struct RenderRunIdentity: Codable, Equatable, Sendable {
    public let runID: String
    public let sceneID: String
    public let renderer: RenderKind
    public let formatVersion: Int
    public let width: Int
    public let height: Int
    public let startedAt: String

    public init(
        runID: String,
        sceneID: String,
        renderer: RenderKind,
        formatVersion: Int,
        width: Int,
        height: Int,
        startedAt: String
    ) throws {
        guard RenderProtocol.isValidIdentifier(runID), RenderProtocol.isValidIdentifier(sceneID) else {
            throw RenderProtocolError.invalidIdentifier
        }
        guard formatVersion == RenderProtocol.formatVersion else {
            throw RenderProtocolError.unsupportedFormatVersion
        }
        guard width == RenderProtocol.viewportWidth, height == RenderProtocol.viewportHeight else {
            throw RenderProtocolError.invalidDimensions
        }
        guard RenderProtocol.isValidIdentifier(startedAt) else {
            throw RenderProtocolError.invalidIdentifier
        }
        self.runID = runID
        self.sceneID = sceneID
        self.renderer = renderer
        self.formatVersion = formatVersion
        self.width = width
        self.height = height
        self.startedAt = startedAt
    }
}

public struct RenderRunEvent: Codable, Equatable, Sendable {
    public let sequence: Int
    public let name: String
    public let milliseconds: Int

    public init(sequence: Int, name: String, milliseconds: Int) throws {
        guard sequence >= 0, sequence <= 1_000_000, milliseconds >= 0 else {
            throw RenderRunEvent.Error.invalidValue
        }
        guard RenderProtocol.isValidIdentifier(name), name.utf8.count <= 32 else {
            throw RenderRunEvent.Error.invalidName
        }
        self.sequence = sequence
        self.name = name
        self.milliseconds = milliseconds
    }

    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidValue
        case invalidName
    }
}

public struct RenderRunMetrics: Codable, Equatable, Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case negativeValue
        case invalidBounds
        case invalidTerminalCode
    }

    public let totalMilliseconds: Int
    public let providerMilliseconds: Int
    public let prepareMilliseconds: Int
    public let transferMilliseconds: Int
    public let validateMilliseconds: Int
    public let renderMilliseconds: Int
    public let bytes: Int
    public let chunks: Int
    public let retries: Int
    public let primitives: Int
    public let providerCalls: Int
    public let ackDurationsMilliseconds: [Int]
    public let ackP50Milliseconds: Int?
    public let ackP95Milliseconds: Int?
    public let ackMaxMilliseconds: Int?
    public let terminalCode: String

    public init(
        totalMilliseconds: Int,
        providerMilliseconds: Int,
        prepareMilliseconds: Int,
        transferMilliseconds: Int,
        validateMilliseconds: Int,
        renderMilliseconds: Int,
        bytes: Int,
        chunks: Int,
        retries: Int,
        primitives: Int,
        providerCalls: Int,
        ackDurationsMilliseconds: [Int],
        terminalCode: String
    ) throws {
        let durations = [
            totalMilliseconds, providerMilliseconds, prepareMilliseconds,
            transferMilliseconds, validateMilliseconds, renderMilliseconds,
            bytes, chunks, retries, primitives, providerCalls,
        ] + ackDurationsMilliseconds
        guard durations.allSatisfy({ $0 >= 0 }) else { throw Error.negativeValue }
        guard bytes <= RenderProtocol.maximumPayloadBytes,
              primitives <= RenderProtocol.maximumPrimitives else {
            throw Error.invalidBounds
        }
        guard RenderProtocol.isValidIdentifier(terminalCode), terminalCode.utf8.count <= 32 else {
            throw Error.invalidTerminalCode
        }
        self.totalMilliseconds = totalMilliseconds
        self.providerMilliseconds = providerMilliseconds
        self.prepareMilliseconds = prepareMilliseconds
        self.transferMilliseconds = transferMilliseconds
        self.validateMilliseconds = validateMilliseconds
        self.renderMilliseconds = renderMilliseconds
        self.bytes = bytes
        self.chunks = chunks
        self.retries = retries
        self.primitives = primitives
        self.providerCalls = providerCalls
        self.ackDurationsMilliseconds = ackDurationsMilliseconds
        self.ackP50Milliseconds = Self.percentile(ackDurationsMilliseconds, percentile: 0.50)
        self.ackP95Milliseconds = Self.percentile(ackDurationsMilliseconds, percentile: 0.95)
        self.ackMaxMilliseconds = ackDurationsMilliseconds.max()
        self.terminalCode = terminalCode
    }

    private enum CodingKeys: String, CodingKey {
        case totalMilliseconds = "totalMs"
        case providerMilliseconds = "providerMs"
        case prepareMilliseconds = "prepareMs"
        case transferMilliseconds = "transferMs"
        case validateMilliseconds = "validateMs"
        case renderMilliseconds = "renderMs"
        case bytes, chunks, retries, primitives, providerCalls
        case ackDurationsMilliseconds = "ackDurationsMs"
        case ackP50Milliseconds = "ackP50Ms"
        case ackP95Milliseconds = "ackP95Ms"
        case ackMaxMilliseconds = "ackMaxMs"
        case terminalCode
    }

    private static func percentile(_ values: [Int], percentile: Double) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = max(1, Int(ceil(percentile * Double(sorted.count))))
        return sorted[min(sorted.count, rank) - 1]
    }
}

public struct RenderRunRecord: Codable, Equatable, Sendable {
    public let identity: RenderRunIdentity
    public let events: [RenderRunEvent]
    public let metrics: RenderRunMetrics
    public let payloadSHA256: String

    public init(
        identity: RenderRunIdentity,
        events: [RenderRunEvent],
        metrics: RenderRunMetrics,
        payloadSHA256: String
    ) {
        self.identity = identity
        self.events = events
        self.metrics = metrics
        self.payloadSHA256 = payloadSHA256
    }

    public func sanitizedExportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public func identityData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(identity)
    }

    public func eventsJSONLData() throws -> Data {
        var output = Data()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        for event in events {
            output.append(try encoder.encode(event))
            output.append(0x0A)
        }
        return output
    }

    public func metricsData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(metrics)
    }
}
