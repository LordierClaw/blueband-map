import CoreGraphics
import Foundation
import ImageIO
import BlueBandMapCore

enum IndexedPNGEncoder {
    private struct Sample {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
        let count: Int
    }

    enum Error: Swift.Error, Equatable {
        case unsupportedRaster
        case imageCreationFailed
        case destinationCreationFailed
        case encodingFailed
        case payloadTooLarge
    }

    static func encode(_ raster: IndexedRaster) throws -> Data {
        guard raster.width == RenderProtocol.viewportWidth,
              raster.height == RenderProtocol.viewportHeight,
              raster.pixels.allSatisfy({ $0 <= IndexedRaster.Palette.current.rawValue }) else {
            throw Error.unsupportedRaster
        }

        return try encodeIndexed(
            width: raster.width,
            height: raster.height,
            pixels: raster.pixels,
            palette: [
                (0, 0, 0),
                (64, 80, 96),
                (220, 224, 228),
                (255, 180, 0),
            ]
        )
    }

    static func quantize(_ png: Data, maximumColors: Int) throws -> Data {
        guard (2...256).contains(maximumColors),
              let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width > 0, image.height > 0 else {
            throw Error.unsupportedRaster
        }
        var rgba = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let decoded = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard decoded else { throw Error.imageCreationFailed }

        var histogram: [UInt32: Int] = [:]
        for offset in stride(from: 0, to: rgba.count, by: 4) {
            let color = UInt32(rgba[offset]) << 16 | UInt32(rgba[offset + 1]) << 8 | UInt32(rgba[offset + 2])
            histogram[color, default: 0] += 1
        }
        var boxes = [histogram.map { color, count in
            Sample(
                red: UInt8((color >> 16) & 0xFF),
                green: UInt8((color >> 8) & 0xFF),
                blue: UInt8(color & 0xFF),
                count: count
            )
        }]
        while boxes.count < maximumColors {
            let candidates = boxes.indices.filter { boxes[$0].count > 1 }
            guard let index = candidates.max(by: { splitScore(boxes[$0]) < splitScore(boxes[$1]) }) else { break }
            let samples = boxes.remove(at: index)
            let channel = widestChannel(samples)
            let sorted = samples.sorted { component($0, channel) < component($1, channel) }
            let half = sorted.reduce(0) { $0 + $1.count } / 2
            var total = 0
            var split = 1
            for sampleIndex in 0..<(sorted.count - 1) {
                total += sorted[sampleIndex].count
                if total >= half { split = sampleIndex + 1; break }
            }
            boxes.append(Array(sorted[..<split]))
            boxes.append(Array(sorted[split...]))
        }
        let palette = boxes.map { samples -> (UInt8, UInt8, UInt8) in
            let total = samples.reduce(0) { $0 + $1.count }
            return (
                UInt8(samples.reduce(0) { $0 + Int($1.red) * $1.count } / total),
                UInt8(samples.reduce(0) { $0 + Int($1.green) * $1.count } / total),
                UInt8(samples.reduce(0) { $0 + Int($1.blue) * $1.count } / total)
            )
        }
        var indices = [UInt8]()
        indices.reserveCapacity(image.width * image.height)
        for offset in stride(from: 0, to: rgba.count, by: 4) {
            let red = Int(rgba[offset]), green = Int(rgba[offset + 1]), blue = Int(rgba[offset + 2])
            let nearest = palette.indices.min { lhs, rhs in
                distance(red, green, blue, palette[lhs]) < distance(red, green, blue, palette[rhs])
            } ?? 0
            indices.append(UInt8(nearest))
        }
        return try encodeIndexed(width: image.width, height: image.height, pixels: indices, palette: palette)
    }

    private static func encodeIndexed(
        width: Int,
        height: Int,
        pixels: [UInt8],
        palette: [(UInt8, UInt8, UInt8)]
    ) throws -> Data {
        let colorTable = palette.flatMap { [$0.0, $0.1, $0.2] }
        let baseColorSpace = CGColorSpaceCreateDeviceRGB()
        let colorSpace = colorTable.withUnsafeBufferPointer { table in
            CGColorSpace(
                indexedBaseSpace: baseColorSpace,
                last: palette.count - 1,
                colorTable: table.baseAddress!
            )
        }
        guard let colorSpace else { throw Error.imageCreationFailed }
        let provider = CGDataProvider(data: Data(pixels) as CFData)
        guard let provider,
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: 0),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw Error.imageCreationFailed
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
            throw Error.destinationCreationFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Error.encodingFailed }
        let data = output as Data
        guard data.count <= RenderProtocol.maximumPayloadBytes else { throw Error.payloadTooLarge }
        return data
    }

    private static func widestChannel(_ samples: [Sample]) -> Int {
        let ranges = (0..<3).map { channel -> Int in
            let values = samples.map { component($0, channel) }
            return Int(values.max() ?? 0) - Int(values.min() ?? 0)
        }
        return ranges.indices.max(by: { ranges[$0] < ranges[$1] }) ?? 0
    }

    private static func splitScore(_ samples: [Sample]) -> Int {
        let channel = widestChannel(samples)
        let values = samples.map { component($0, channel) }
        return (Int(values.max() ?? 0) - Int(values.min() ?? 0)) * samples.reduce(0) { $0 + $1.count }
    }

    private static func component(_ sample: Sample, _ channel: Int) -> UInt8 {
        channel == 0 ? sample.red : channel == 1 ? sample.green : sample.blue
    }

    private static func distance(_ red: Int, _ green: Int, _ blue: Int, _ color: (UInt8, UInt8, UInt8)) -> Int {
        let dr = red - Int(color.0), dg = green - Int(color.1), db = blue - Int(color.2)
        return dr * dr + dg * dg + db * db
    }
}
