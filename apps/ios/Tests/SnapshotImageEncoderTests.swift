import CoreGraphics
import ImageIO
import XCTest
import BlueBandMapCore
@testable import BlueBandMap

final class SnapshotImageEncoderTests: XCTestCase {
    func testRepresentativeMapAvoidsUnnecessaryStopAndWaitChunks() throws {
        let source = try representativeMap(width: 424, height: 1040)
        let output = try SnapshotImageEncoder.encode(source)
        let png = try SnapshotPNGEncoder.encode(source, profiles: [.colors16Labels], blockSizes: [1])
        print("ENCODER baseline=\(output.data.count) indexed=\(png.data.count) pngPSNR=\(try psnr(source: source, decoded: decode(png.data)))")
        XCTAssertLessThanOrEqual(output.data.count, png.data.count,
                                 "do not send extra BLE chunks when a full-resolution map is smaller")
        XCTAssertGreaterThan(try psnr(source: source, decoded: decode(output.data)), 27)
        XCTAssertEqual(output.pixelBlockSize, 1)
    }

    func testRepresentativeRotatedMapSelectsTheBestBoundedJPEG() throws {
        let source = try representativeMap(width: 424, height: 1_040)
        let output = try SnapshotImageEncoder.encode(source)

        XCTAssertEqual(output.format, .jpeg)
        XCTAssertNotNil(output.jpegQuality)
        XCTAssertLessThanOrEqual(output.data.count, RenderProtocol.maximumPayloadBytes)
        XCTAssertEqual(Array(output.data.prefix(2)), [0xff, 0xd8])
        let decoded = try decode(output.data)
        XCTAssertEqual(decoded.width, 212)
        XCTAssertEqual(decoded.height, 520)
        XCTAssertGreaterThan(try psnr(source: source, decoded: decoded), 27)
    }

    func testFallsBackToBoundedIndexedPNGWhenJPEGIsUnavailable() throws {
        let output = try SnapshotImageEncoder.encode(
            noisyImage(width: 212, height: 520), jpegQualities: []
        )

        XCTAssertEqual(output.format, .png)
        XCTAssertNil(output.jpegQuality)
        XCTAssertLessThanOrEqual(output.data.count, RenderProtocol.maximumPayloadBytes)
        XCTAssertEqual(Array(output.data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        let decoded = try decode(output.data)
        XCTAssertEqual(decoded.width, 212)
        XCTAssertEqual(decoded.height, 520)
    }

    private func representativeMap(width: Int, height: Int) throws -> CGImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw SnapshotImageEncoder.Error.imageCreationFailed }
        context.setFillColor(CGColor(red: 5 / 255, green: 14 / 255, blue: 22 / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 40 / 255, green: 52 / 255, blue: 63 / 255, alpha: 1))
        for row in 0..<9 {
            for column in 0..<4 {
                context.fill(CGRect(x: 28 + column * 94, y: 60 + row * 102, width: 64, height: 62))
            }
        }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(CGColor(red: 70 / 255, green: 90 / 255, blue: 116 / 255, alpha: 1))
        context.setLineWidth(22)
        context.move(to: CGPoint(x: 0, y: 900))
        context.addLine(to: CGPoint(x: 400, y: 80))
        context.strokePath()
        context.setStrokeColor(CGColor(red: 22 / 255, green: 140 / 255, blue: 1, alpha: 1))
        context.setLineWidth(12)
        context.move(to: CGPoint(x: 210, y: 1_040))
        context.addLine(to: CGPoint(x: 210, y: 700))
        context.addLine(to: CGPoint(x: 80, y: 390))
        context.addLine(to: CGPoint(x: 330, y: 80))
        context.strokePath()
        return try XCTUnwrap(context.makeImage())
    }

    private func noisyImage(width: Int, height: Int) throws -> CGImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        var state: UInt32 = 0xC0FFEE
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            for component in 0..<3 {
                state = 1_664_525 &* state &+ 1_013_904_223
                pixels[offset + component] = UInt8(truncatingIfNeeded: state >> 24)
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        return try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }

    private func decode(_ data: Data) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func psnr(source: CGImage, decoded: CGImage) throws -> Double {
        let expected = try SnapshotImageEncoder.downsample(source)
        let left = try rgba(expected), right = try rgba(decoded)
        let error = zip(left, right).reduce(0.0) { total, values in
            let difference = Double(values.0) - Double(values.1)
            return total + difference * difference
        } / Double(left.count)
        return error == 0 ? .infinity : 10 * log10(255 * 255 / error)
    }

    private func rgba(_ image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: 212 * 520 * 4)
        guard let context = CGContext(
            data: &pixels, width: 212, height: 520, bitsPerComponent: 8,
            bytesPerRow: 212 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw SnapshotImageEncoder.Error.imageCreationFailed }
        context.draw(image, in: CGRect(x: 0, y: 0, width: 212, height: 520))
        return pixels
    }
}
