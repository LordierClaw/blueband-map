import Foundation
import XCTest
import BlueBandCore
@testable import BlueBandMapCore

final class MapAssetTransferPlanTests: XCTestCase {
    private let envelopeID = String(repeating: "\\", count: 32)

    func testMakeProducesOrderedBoundedStepsThatReconstructAsset() throws {
        let data = pngData(byteCount: 1_001, width: 212, height: 360)
        let asset = try MapAsset.png(data: data, expectedWidth: 212, expectedHeight: 360)

        let steps = try MapAssetTransferPlan.make(asset: asset)

        XCTAssertEqual(steps.first?.topic, "map.asset.begin")
        XCTAssertEqual(steps.first?.body, [
            "asset": .string(asset.id),
            "bytes": .number(Double(asset.byteCount)),
            "mime": .string(asset.mimeType),
            "sha256": .string(asset.sha256),
            "width": .number(Double(asset.width)),
            "height": .number(Double(asset.height)),
        ])
        XCTAssertEqual(steps.last?.topic, "map.asset.end")
        XCTAssertEqual(steps.last?.body, ["asset": .string(asset.id)])
        XCTAssertTrue(steps.dropFirst().dropLast().allSatisfy { $0.topic == "map.asset.chunk" })

        var reconstructed = Data()
        var expectedOffset = 0
        let chunkSteps = Array(steps.dropFirst().dropLast())

        for (index, step) in chunkSteps.enumerated() {
            XCTAssertEqual(step.body["asset"], .string(asset.id))
            XCTAssertEqual(Set(step.body.keys), ["asset", "offset", "data"])
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

        let steps = try MapAssetTransferPlan.make(asset: asset)

        var expectedOffset = 0
        var reconstructed = Data()
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
                ])
            case "map.asset.chunk":
                XCTAssertNotEqual(index, 0)
                XCTAssertNotEqual(index, steps.index(before: steps.endIndex))
                XCTAssertEqual(step.body["asset"], .string(asset.id))
                XCTAssertEqual(step.body["offset"], .number(Double(expectedOffset)))
                let chunk = try XCTUnwrap(Data(base64Encoded: try string("data", in: step.body)))
                expectedOffset += chunk.count
                reconstructed.append(chunk)
            case "map.asset.end":
                XCTAssertEqual(index, steps.index(before: steps.endIndex))
                XCTAssertEqual(step.body, ["asset": .string(asset.id)])
            default:
                XCTFail("Unexpected transfer topic \(step.topic)")
            }
        }

        XCTAssertEqual(expectedOffset, asset.byteCount)
        XCTAssertEqual(reconstructed, asset.data)
    }

    func testMakeHandlesMapAssetBackedByNonZeroIndexDataSlice() throws {
        let original = pngData(byteCount: 1_001, width: 212, height: 360)
        let prefixed = Data([0xff]) + original
        let slice = prefixed.dropFirst()
        let asset = try MapAsset.png(data: slice, expectedWidth: 212, expectedHeight: 360)
        XCTAssertNotEqual(asset.data.startIndex, 0)

        let steps = try MapAssetTransferPlan.make(asset: asset)

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
            try MapAssetTransferPlan.make(asset: asset),
            try MapAssetTransferPlan.make(asset: asset)
        )
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
