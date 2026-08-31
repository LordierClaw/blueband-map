import CoreGraphics
import Foundation
import ImageIO
import BlueBandMapCore

struct SnapshotPNGOutput: Sendable {
    let data: Data
    let profile: SnapshotPaletteProfile
    let colorCount: Int
    let durationMilliseconds: Int
}

enum SnapshotPNGEncoder {
    enum Error: Swift.Error, Equatable {
        case unsupportedImage
        case imageCreationFailed
        case destinationCreationFailed
        case encodingFailed
        case payloadTooLarge(Int)
    }

    static func encode(
        _ image: CGImage,
        profiles: [SnapshotPaletteProfile] = SnapshotPaletteProfile.allCases
    ) throws -> SnapshotPNGOutput {
        guard image.width == RenderProtocol.viewportWidth,
              image.height == RenderProtocol.viewportHeight,
              !profiles.isEmpty else { throw Error.unsupportedImage }
        let started = nowMilliseconds()
        let pixels = try rgbaPixels(image)
        var lastSize = 0
        for profile in profiles {
            let palette = palette(for: profile)
            let indices = quantize(pixels, palette: palette)
            let data = try encodeIndexed(indices, width: image.width, height: image.height, palette: palette)
            lastSize = data.count
            if data.count <= RenderProtocol.maximumPayloadBytes {
                return SnapshotPNGOutput(
                    data: data,
                    profile: profile,
                    colorCount: palette.count,
                    durationMilliseconds: max(0, nowMilliseconds() - started)
                )
            }
        }
        throw Error.payloadTooLarge(lastSize)
    }

    private static func rgbaPixels(_ image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw Error.unsupportedImage }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }

    private static func quantize(_ pixels: [UInt8], palette: [(UInt8, UInt8, UInt8)]) -> [UInt8] {
        var result = [UInt8]()
        result.reserveCapacity(pixels.count / 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[offset]), green = Int(pixels[offset + 1]), blue = Int(pixels[offset + 2])
            var best = 0, bestDistance = Int.max
            for (index, color) in palette.enumerated() {
                let dr = red - Int(color.0), dg = green - Int(color.1), db = blue - Int(color.2)
                let distance = dr * dr + dg * dg + db * db
                if distance < bestDistance { best = index; bestDistance = distance }
            }
            result.append(UInt8(best))
        }
        return result
    }

    private static func encodeIndexed(
        _ indices: [UInt8],
        width: Int,
        height: Int,
        palette: [(UInt8, UInt8, UInt8)]
    ) throws -> Data {
        let table = palette.flatMap { [$0.0, $0.1, $0.2] }
        let colorSpace = table.withUnsafeBufferPointer {
            CGColorSpace(indexedBaseSpace: CGColorSpaceCreateDeviceRGB(), last: palette.count - 1, colorTable: $0.baseAddress!)
        }
        guard let colorSpace,
              let provider = CGDataProvider(data: Data(indices) as CFData),
              let indexedImage = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                bytesPerRow: width, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: 0),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else { throw Error.imageCreationFailed }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
            throw Error.destinationCreationFailed
        }
        CGImageDestinationAddImage(destination, indexedImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw Error.encodingFailed }
        return output as Data
    }

    private static func palette(for profile: SnapshotPaletteProfile) -> [(UInt8, UInt8, UInt8)] {
        let base: [(UInt8, UInt8, UInt8)] = [
            (5, 14, 22), (16, 28, 35), (28, 43, 50), (43, 58, 62),
            (58, 75, 75), (76, 92, 86), (96, 111, 98), (119, 132, 111),
            (142, 151, 124), (164, 169, 140), (184, 185, 157), (201, 200, 176),
            (218, 216, 194), (232, 230, 211), (244, 243, 229), (255, 255, 255),
            (0, 79, 110), (0, 119, 150), (0, 163, 190), (0, 229, 255),
            (32, 98, 57), (58, 130, 75), (91, 159, 96), (135, 186, 124),
            (91, 62, 45), (130, 91, 65), (171, 126, 91), (209, 165, 119),
            (118, 41, 54), (166, 57, 72), (211, 91, 99), (244, 139, 132),
        ]
        return profile.colorCount == 32 ? base : Array(base.prefix(16))
    }

    private static func nowMilliseconds() -> Int { Int(Date().timeIntervalSince1970 * 1_000) }
}
