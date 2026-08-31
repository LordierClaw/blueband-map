import CoreGraphics
import ImageIO
import XCTest
import BlueBandMapCore
@testable import BlueBandMap

final class SnapshotPNGEncoderTests: XCTestCase {
    func testEncodesFullScreenIndexedPNGUsingFirstAdmittedProfile() throws {
        let image = try solidImage(width: 212, height: 520)
        let output = try SnapshotPNGEncoder.encode(image)

        XCTAssertEqual(output.profile, .colors32Labels)
        XCTAssertEqual(output.colorCount, 32)
        XCTAssertLessThanOrEqual(output.data.count, RenderProtocol.maximumPayloadBytes)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(output.data as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(decoded.width, 212)
        XCTAssertEqual(decoded.height, 520)
    }

    func testRejectsWhenNoRequestedProfileFitsEightKiB() throws {
        let image = try noisyImage(width: 212, height: 520)
        XCTAssertThrowsError(try SnapshotPNGEncoder.encode(image, profiles: [.colors32Labels])) { error in
            guard case SnapshotPNGEncoder.Error.payloadTooLarge = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    private func solidImage(width: Int, height: Int) throws -> CGImage {
        try image(width: width, height: height, pixels: [UInt8](repeating: 0x80, count: width * height * 4))
    }

    private func noisyImage(width: Int, height: Int) throws -> CGImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        var state: UInt32 = 0xC0FFEE
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            state = 1_664_525 &* state &+ 1_013_904_223
            pixels[offset] = UInt8(truncatingIfNeeded: state >> 24)
            state = 1_664_525 &* state &+ 1_013_904_223
            pixels[offset + 1] = UInt8(truncatingIfNeeded: state >> 24)
            state = 1_664_525 &* state &+ 1_013_904_223
            pixels[offset + 2] = UInt8(truncatingIfNeeded: state >> 24)
        }
        return try image(width: width, height: height, pixels: pixels)
    }

    private func image(width: Int, height: Int, pixels: [UInt8]) throws -> CGImage {
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        return try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }
}
