import CoreGraphics
import Foundation
import ImageIO
import BlueBandMapCore

struct SnapshotImageOutput: Sendable {
    let data: Data
    let format: RenderFormat
    let jpegQuality: Int?
    let colorCount: Int
    let pixelBlockSize: Int
    let durationMilliseconds: Int
}

enum SnapshotImageEncoder {
    enum Error: Swift.Error, Equatable {
        case unsupportedImage
        case imageCreationFailed
        case payloadTooLarge(Int)
    }

    static let defaultJPEGQualities = [50, 45, 40, 35, 30, 25, 20, 15, 10]

    static func encode(
        _ image: CGImage,
        jpegQualities: [Int] = defaultJPEGQualities
    ) throws -> SnapshotImageOutput {
        let started = nowMilliseconds()
        let downsampled = try downsample(image)
        var rejectedBytes = 0
        for quality in jpegQualities where (1...100).contains(quality) {
            guard let data = jpeg(downsampled, quality: quality) else { continue }
            rejectedBytes = data.count
            if data.count <= RenderProtocol.maximumPayloadBytes {
                return SnapshotImageOutput(
                    data: data,
                    format: .jpeg,
                    jpegQuality: quality,
                    colorCount: 0,
                    pixelBlockSize: 1,
                    durationMilliseconds: max(0, nowMilliseconds() - started)
                )
            }
        }
        do {
            let png = try SnapshotPNGEncoder.encode(
                downsampled,
                profiles: [.colors16Labels],
                blockSizes: [1, 2, 4, 8]
            )
            return SnapshotImageOutput(
                data: png.data,
                format: .png,
                jpegQuality: nil,
                colorCount: png.colorCount,
                pixelBlockSize: png.pixelBlockSize,
                durationMilliseconds: max(0, nowMilliseconds() - started)
            )
        } catch let SnapshotPNGEncoder.Error.payloadTooLarge(bytes) {
            throw Error.payloadTooLarge(max(rejectedBytes, bytes))
        }
    }

    static func downsample(_ image: CGImage) throws -> CGImage {
        let width = RenderProtocol.viewportWidth
        let height = RenderProtocol.viewportHeight
        guard (image.width == width && image.height == height) ||
                (image.width == width * 2 && image.height == height * 2) else {
            throw Error.unsupportedImage
        }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw Error.imageCreationFailed }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let output = context.makeImage() else { throw Error.imageCreationFailed }
        return output
    }

    private static func jpeg(_ image: CGImage, quality: Int) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: Double(quality) / 100
        ] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    private static func nowMilliseconds() -> Int { Int(Date().timeIntervalSince1970 * 1_000) }
}
