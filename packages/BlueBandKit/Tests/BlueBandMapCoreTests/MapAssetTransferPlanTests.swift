import Foundation
import XCTest
import BlueBandCore
@testable import BlueBandMapCore

final class MapAssetTransferPlanTests: XCTestCase {
    private let envelopeID = String(repeating: "\\", count: 32)
    private let runID = "run-0123456789abcdef"

    func testMakeProducesOrderedBoundedStepsThatReconstructAsset() throws {
        let data = pngData(byteCount: 1_001, width: 212, height: 360)
        let asset = try MapAsset.png(data: data, expectedWidth: 212, expectedHeight: 360)

        let steps = try MapAssetTransferPlan.make(asset: asset, runID: runID)

        XCTAssertEqual(steps.first?.topic, "map.asset.begin")
        XCTAssertEqual(steps.first?.body, [
            "asset": .string(asset.id),
            "bytes": .number(Double(asset.byteCount)),
            "mime": .string(asset.mimeType),
            "sha256": .string(asset.sha256),
            "width": .number(Double(asset.width)),
            "height": .number(Double(asset.height)),
            "run": .string(runID),
        ])
        XCTAssertEqual(steps.last?.topic, "map.asset.end")
        XCTAssertEqual(steps.last?.body, ["asset": .string(asset.id), "run": .string(runID)])
        XCTAssertTrue(steps.dropFirst().dropLast().allSatisfy { $0.topic == "map.asset.chunk" })

        var reconstructed = Data()
        var expectedOffset = 0
        let chunkSteps = Array(steps.dropFirst().dropLast())

        for (index, step) in chunkSteps.enumerated() {
            XCTAssertEqual(step.body["asset"], .string(asset.id))
            XCTAssertEqual(step.body["run"], .string(runID))
            XCTAssertEqual(Set(step.body.keys), ["asset", "offset", "data", "run"])
            let offset = try number("offset", in: step.body)
            let encodedChunk = try string("data", in: step.body)
            let chunk = try XCTUnwrap(Data(base64Encoded: encodedChunk))

            XCTAssertEqual(offset, expectedOffset)
            XCTAssertLessThanOrEqual(chunk.count, 320)
            expectedOffset += chunk.count
            reconstructed.append(chunk)

            if index < chunkSteps.index(before: chunkSteps.endIndex) {
                if chunk.count == 320 {
                    continue
                }
                let logicalEnd = offset + chunk.count + 1
                let startIndex = asset.data.index(asset.data.startIndex, offsetBy: offset)
                let endIndex = asset.data.index(asset.data.startIndex, offsetBy: logicalEnd)
                let largerChunk = Data(asset.data[startIndex..<endIndex])
                let largerBody: [String: JSONValue] = [
                    "asset": .string(asset.id),
                    "offset": .number(Double(offset)),
                    "data": .string(largerChunk.base64EncodedString()),
                    "run": .string(String(repeating: "r", count: MapAssetTransferPlan.maximumRunIDBytes)),
                ]
                let largerEnvelope = ApplicationEnvelope.message(
                    id: envelopeID,
                    source: .ios,
                    topic: step.topic,
                    body: largerBody
                )
                XCTAssertThrowsError(try largerEnvelope.encoded()) { error in
                    XCTAssertEqual(error as? ApplicationEnvelope.Error, .tooLarge)
                }
            }
        }

        XCTAssertEqual(expectedOffset, asset.byteCount)
        XCTAssertEqual(reconstructed, asset.data)

        for step in steps {
            let envelope = ApplicationEnvelope.message(
                id: envelopeID,
                source: .ios,
                topic: step.topic,
                body: step.body
            )
            XCTAssertLessThanOrEqual(try envelope.encoded().count, ApplicationEnvelope.maximumEncodedSize)
        }
    }

    func testMakeHandlesMaximumMapAssetSize() throws {
        let data = pngData(byteCount: MapAsset.maximumPNGBytes, width: 212, height: 360)
        let asset = try MapAsset.png(data: data, expectedWidth: 212, expectedHeight: 360)

        let maximumRunID = String(repeating: "r", count: MapAssetTransferPlan.maximumRunIDBytes)
        let steps = try MapAssetTransferPlan.make(asset: asset, runID: maximumRunID)

        var expectedOffset = 0
        var reconstructed = Data()
        var observedWorstCaseChunk = false
        reconstructed.reserveCapacity(asset.byteCount)

        for (index, step) in steps.enumerated() {
            let envelope = ApplicationEnvelope.message(
                id: envelopeID,
                source: .ios,
                topic: step.topic,
                body: step.body
            )
            XCTAssertLessThanOrEqual(try envelope.encoded().count, ApplicationEnvelope.maximumEncodedSize)

            switch step.topic {
            case "map.asset.begin":
                XCTAssertEqual(index, 0)
                XCTAssertEqual(step.body, [
                    "asset": .string(asset.id),
                    "bytes": .number(Double(asset.byteCount)),
                    "mime": .string(asset.mimeType),
                    "sha256": .string(asset.sha256),
                    "width": .number(Double(asset.width)),
                    "height": .number(Double(asset.height)),
                    "run": .string(maximumRunID),
                ])
            case "map.asset.chunk":
                XCTAssertNotEqual(index, 0)
                XCTAssertNotEqual(index, steps.index(before: steps.endIndex))
                XCTAssertEqual(step.body["asset"], .string(asset.id))
                XCTAssertEqual(step.body["run"], .string(maximumRunID))
                XCTAssertEqual(step.body["offset"], .number(Double(expectedOffset)))
                let chunk = try XCTUnwrap(Data(base64Encoded: try string("data", in: step.body)))
                if expectedOffset >= 100_000, chunk.count == 210 {
                    XCTAssertEqual(try envelope.encoded().count, ApplicationEnvelope.maximumEncodedSize)
                    observedWorstCaseChunk = true
                }
                expectedOffset += chunk.count
                reconstructed.append(chunk)
            case "map.asset.end":
                XCTAssertEqual(index, steps.index(before: steps.endIndex))
                XCTAssertEqual(step.body, ["asset": .string(asset.id), "run": .string(maximumRunID)])
            default:
                XCTFail("Unexpected transfer topic \(step.topic)")
            }
        }

        XCTAssertEqual(expectedOffset, asset.byteCount)
        XCTAssertEqual(reconstructed, asset.data)
        XCTAssertTrue(observedWorstCaseChunk)
    }

    func testMakeHandlesMapAssetBackedByNonZeroIndexDataSlice() throws {
        let original = pngData(byteCount: 1_001, width: 212, height: 360)
        let prefixed = Data([0xff]) + original
        let slice = prefixed.dropFirst()
        let asset = try MapAsset.png(data: slice, expectedWidth: 212, expectedHeight: 360)
        XCTAssertNotEqual(asset.data.startIndex, 0)

        let steps = try MapAssetTransferPlan.make(asset: asset, runID: runID)

        let reconstructed = try steps.dropFirst().dropLast().reduce(into: Data()) { result, step in
            result.append(try XCTUnwrap(Data(base64Encoded: try string("data", in: step.body))))
        }
        XCTAssertEqual(reconstructed, original)
    }

    func testMakeIsDeterministic() throws {
        let asset = try MapAsset.png(
            data: pngData(byteCount: 1_001, width: 212, height: 360),
            expectedWidth: 212,
            expectedHeight: 360
        )

        XCTAssertEqual(
            try MapAssetTransferPlan.make(asset: asset, runID: runID),
            try MapAssetTransferPlan.make(asset: asset, runID: runID)
        )
    }

    func testRunIDValidationIsBoundedASCIIAndExactAcrossEveryStep() throws {
        let asset = try MapAsset.png(
            data: pngData(byteCount: 64, width: 212, height: 360),
            expectedWidth: 212,
            expectedHeight: 360
        )
        let valid = ["r", "run-0123456789abcdef", String(repeating: "z", count: 24)]
        for runID in valid {
            let steps = try MapAssetTransferPlan.make(asset: asset, runID: runID)
            XCTAssertTrue(steps.allSatisfy { $0.body["run"] == .string(runID) })
        }

        for runID in ["", "UPPER", "run_under", "run space", "é", String(repeating: "r", count: 25)] {
            XCTAssertThrowsError(try MapAssetTransferPlan.make(asset: asset, runID: runID)) { error in
                XCTAssertEqual(error as? MapAssetTransferPlan.Error, .invalidRunID)
            }
        }
    }

    func testIndependentRunCorrelatedBodyVectorIsExact() throws {
        let asset = try MapAsset.png(
            data: pngData(byteCount: 29, width: 212, height: 360),
            expectedWidth: 212,
            expectedHeight: 360
        )
        let steps = try MapAssetTransferPlan.make(asset: asset, runID: "run-vector-0001")

        XCTAssertEqual(steps.first?.body["run"], .string("run-vector-0001"))
        XCTAssertEqual(steps.dropFirst().first?.body, [
            "asset": .string(asset.id),
            "data": .string(asset.data.base64EncodedString()),
            "offset": .number(0),
            "run": .string("run-vector-0001"),
        ])
        XCTAssertEqual(steps.last?.body, [
            "asset": .string(asset.id),
            "run": .string("run-vector-0001"),
        ])
    }

    private func string(_ key: String, in body: [String: JSONValue]) throws -> String {
        guard case let .string(value)? = body[key] else {
            return try XCTUnwrap(nil, "Expected string body value for \(key)")
        }
        return value
    }

    private func number(_ key: String, in body: [String: JSONValue]) throws -> Int {
        guard case let .number(value)? = body[key] else {
            return try XCTUnwrap(nil, "Expected numeric body value for \(key)")
        }
        return Int(value)
    }
}

private func pngData(byteCount: Int, width: UInt32, height: UInt32) -> Data {
    precondition(byteCount >= 29)
    var bytes: [UInt8] = [
        137, 80, 78, 71, 13, 10, 26, 10,
        0, 0, 0, 13,
        73, 72, 68, 82,
    ]
    bytes.append(contentsOf: bigEndianBytes(width))
    bytes.append(contentsOf: bigEndianBytes(height))
    bytes.append(contentsOf: [8, 6, 0, 0, 0])
    bytes.append(contentsOf: (bytes.count..<byteCount).map { UInt8(truncatingIfNeeded: $0) })
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
