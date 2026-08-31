import Foundation
import BlueBandCore

public struct RenderTransferStep: Equatable, Sendable {
    public let topic: String
    public let body: [String: JSONValue]

    public init(topic: String, body: [String: JSONValue]) {
        self.topic = topic
        self.body = body
    }
}

public enum RenderTransferPlan {
    public enum Error: Swift.Error, Equatable, Sendable {
        case cannotFitChunk
        case invalidRunID
        case invalidSceneID
    }

    public static let maximumRunIDBytes = RenderProtocol.maximumIdentifierBytes
    public static let maximumSceneIDBytes = RenderProtocol.maximumIdentifierBytes
    private static let envelopeID = String(repeating: "\\", count: 32)
    private static let maximumChunkBytes = RenderProtocol.maximumPayloadBytes

    public static func make(asset: RenderAsset, runID: String, sceneID: String) throws -> [RenderTransferStep] {
        guard RenderProtocol.isValidIdentifier(runID) else { throw Error.invalidRunID }
        guard RenderProtocol.isValidIdentifier(sceneID) else { throw Error.invalidSceneID }

        let begin = RenderTransferStep(
            topic: "map.asset.begin",
            body: beginBody(asset: asset, runID: runID, sceneID: sceneID)
        )
        guard fitsEnvelope(begin) else { throw Error.cannotFitChunk }

        var steps = [begin]
        var offset = 0
        while offset < asset.byteCount {
            let chunkByteCount = maximumFittingChunkByteCount(
                for: asset,
                offset: offset,
                runID: runID,
                sceneID: sceneID
            )
            guard chunkByteCount > 0 else { throw Error.cannotFitChunk }
            let step = chunkStep(for: asset, offset: offset, byteCount: chunkByteCount, runID: runID, sceneID: sceneID)
            guard fitsEnvelope(step) else { throw Error.cannotFitChunk }
            steps.append(step)
            offset += chunkByteCount
        }

        let end = RenderTransferStep(
            topic: "map.asset.end",
            body: [
                "asset": .string(asset.id),
                "run": .string(runID),
                "scene": .string(sceneID),
            ]
        )
        guard fitsEnvelope(end) else { throw Error.cannotFitChunk }
        steps.append(end)
        return steps
    }

    private static func beginBody(asset: RenderAsset, runID: String, sceneID: String) -> [String: JSONValue] {
        [
            "asset": .string(asset.id),
            "bytes": .number(Double(asset.byteCount)),
            "mime": .string(asset.format.rawValue),
            "format": .string(asset.format.rawValue),
            "sha256": .string(asset.sha256),
            "width": .number(Double(asset.width)),
            "height": .number(Double(asset.height)),
            "run": .string(runID),
            "scene": .string(sceneID),
            "renderer": .string(asset.kind.rawValue),
            "formatVersion": .number(Double(asset.formatVersion)),
            "primitives": .number(Double(asset.primitives)),
        ]
    }

    private static func maximumFittingChunkByteCount(
        for asset: RenderAsset,
        offset: Int,
        runID: String,
        sceneID: String
    ) -> Int {
        var lowerBound = 1
        var upperBound = min(maximumChunkBytes, asset.byteCount - offset)
        var best = 0
        while lowerBound <= upperBound {
            let candidate = lowerBound + (upperBound - lowerBound) / 2
            let step = chunkStep(
                for: asset,
                offset: offset,
                byteCount: candidate,
                runID: runID,
                sceneID: sceneID
            )
            if fitsEnvelope(step) {
                best = candidate
                lowerBound = candidate + 1
            } else {
                upperBound = candidate - 1
            }
        }
        return best
    }

    private static func chunkStep(
        for asset: RenderAsset,
        offset: Int,
        byteCount: Int,
        runID: String,
        sceneID: String
    ) -> RenderTransferStep {
        let start = asset.data.index(asset.data.startIndex, offsetBy: offset)
        let end = asset.data.index(start, offsetBy: byteCount)
        return RenderTransferStep(
            topic: "map.asset.chunk",
            body: [
                "asset": .string(asset.id),
                "offset": .number(Double(offset)),
                "data": .string(Data(asset.data[start..<end]).base64EncodedString()),
                "run": .string(runID),
                "scene": .string(sceneID),
            ]
        )
    }

    private static func fitsEnvelope(_ step: RenderTransferStep) -> Bool {
        let envelope = ApplicationEnvelope.message(
            id: envelopeID,
            source: .ios,
            topic: step.topic,
            body: step.body
        )
        guard let encoded = try? envelope.encoded() else { return false }
        return encoded.count <= ApplicationEnvelope.maximumEncodedSize
    }
}
