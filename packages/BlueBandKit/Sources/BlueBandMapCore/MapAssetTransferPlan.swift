import Foundation
import BlueBandCore

public struct MapTransferStep: Equatable, Sendable {
    public let topic: String
    public let body: [String: JSONValue]

    public init(topic: String, body: [String: JSONValue]) {
        self.topic = topic
        self.body = body
    }
}

public enum MapAssetTransferPlan {
    public enum Error: Swift.Error, Equatable {
        case cannotFitChunk
        case invalidRunID
    }

    public static let maximumRunIDBytes = 24
    private static let envelopeID = String(repeating: "\\", count: 32)
    private static let maximumChunkBytes = 320
    private static let sizingRunID = String(repeating: "r", count: maximumRunIDBytes)

    public static func make(asset: MapAsset, runID: String) throws -> [MapTransferStep] {
        guard isValidRunID(runID) else {
            throw Error.invalidRunID
        }
        let begin = MapTransferStep(
            topic: "map.asset.begin",
            body: [
                "asset": .string(asset.id),
                "bytes": .number(Double(asset.byteCount)),
                "mime": .string(asset.mimeType),
                "sha256": .string(asset.sha256),
                "width": .number(Double(asset.width)),
                "height": .number(Double(asset.height)),
                "run": .string(runID),
            ]
        )
        guard fitsEnvelope(begin) else {
            throw Error.cannotFitChunk
        }

        var steps = [begin]
        var offset = 0
        while offset < asset.byteCount {
            let chunkByteCount = maximumFittingChunkByteCount(for: asset, offset: offset)
            guard chunkByteCount > 0 else {
                throw Error.cannotFitChunk
            }

            let step = chunkStep(for: asset, offset: offset, byteCount: chunkByteCount, runID: runID)
            guard fitsEnvelope(step) else {
                throw Error.cannotFitChunk
            }
            steps.append(step)
            offset += chunkByteCount
        }

        let end = MapTransferStep(
            topic: "map.asset.end",
            body: ["asset": .string(asset.id), "run": .string(runID)]
        )
        guard fitsEnvelope(end) else {
            throw Error.cannotFitChunk
        }
        steps.append(end)
        return steps
    }

    private static func maximumFittingChunkByteCount(for asset: MapAsset, offset: Int) -> Int {
        var lowerBound = 1
        var upperBound = min(maximumChunkBytes, asset.byteCount - offset)
        var best = 0

        while lowerBound <= upperBound {
            let candidate = lowerBound + (upperBound - lowerBound) / 2
            let step = chunkStep(for: asset, offset: offset, byteCount: candidate, runID: sizingRunID)
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
        for asset: MapAsset,
        offset: Int,
        byteCount: Int,
        runID: String
    ) -> MapTransferStep {
        let start = asset.data.index(asset.data.startIndex, offsetBy: offset)
        let end = asset.data.index(start, offsetBy: byteCount)
        let encodedData = Data(asset.data[start..<end]).base64EncodedString()
        return MapTransferStep(
            topic: "map.asset.chunk",
            body: [
                "asset": .string(asset.id),
                "offset": .number(Double(offset)),
                "data": .string(encodedData),
                "run": .string(runID),
            ]
        )
    }

    public static func isValidRunID(_ runID: String) -> Bool {
        guard (1...maximumRunIDBytes).contains(runID.utf8.count) else { return false }
        return runID.utf8.allSatisfy {
            (48...57).contains($0) || (97...122).contains($0) || $0 == 45
        }
    }

    private static func fitsEnvelope(_ step: MapTransferStep) -> Bool {
        let envelope = ApplicationEnvelope.message(
            id: envelopeID,
            source: .ios,
            topic: step.topic,
            body: step.body
        )
        guard let encoded = try? envelope.encoded() else {
            return false
        }
        return encoded.count <= ApplicationEnvelope.maximumEncodedSize
    }
}
