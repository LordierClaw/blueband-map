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
        case payloadTooLarge
    }

    static func encode(_ raster: IndexedRaster) throws -> Data {
        guard raster.width == RenderProtocol.viewportWidth,
              raster.height == RenderProtocol.viewportHeight,
              raster.pixels.allSatisfy({ $0 <= IndexedRaster.Palette.current.rawValue }) else {
            throw Error.unsupportedRaster
        }

        let colorTable: [UInt8] = [
            0, 0, 0,
            64, 80, 96,
            220, 224, 228,
            255, 180, 0,
        ]
        let baseColorSpace = CGColorSpaceCreateDeviceRGB()
        let colorSpace = colorTable.withUnsafeBufferPointer { table in
            CGColorSpace(
                indexedBaseSpace: baseColorSpace,
                last: 3,
                colorTable: table.baseAddress!
            )
        }
        guard let colorSpace else { throw Error.imageCreationFailed }
        let provider = CGDataProvider(data: Data(raster.pixels) as CFData)
        guard let provider,
              let image = CGImage(
                width: raster.width,
                height: raster.height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: raster.width,
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
}
