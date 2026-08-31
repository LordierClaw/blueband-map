import CoreGraphics
import Foundation
import ImageIO
import BlueBandMapCore

enum IndexedPNGEncoder {
    enum Error: Swift.Error, Equatable {
        case unsupportedRaster
        case imageCreationFailed
        case destinationCreationFailed
        case encodingFailed
        case payloadTooLarge(Int)
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
            pixels: raster.twoBitPixels,
            palette: [
                (5, 14, 22),
                (55, 72, 84),
                (104, 121, 132),
                (0, 229, 255),
            ]
        )
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
                bitsPerComponent: 2,
                bitsPerPixel: 2,
                bytesPerRow: (width + 3) / 4,
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
        guard data.count <= RenderProtocol.maximumPayloadBytes else { throw Error.payloadTooLarge(data.count) }
        return data
    }

}
