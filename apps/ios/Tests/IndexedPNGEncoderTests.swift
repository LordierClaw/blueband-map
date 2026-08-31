import Foundation
import CoreGraphics
import ImageIO
import XCTest
import BlueBandMapCore
@testable import BlueBandMap

final class IndexedPNGEncoderTests: XCTestCase {
    func testProducesBoundedPNGWithTheExpectedViewport() throws {
        let scene = try NavigationScene.synthetic(segmentCount: 40)
        let raster = try IndexedRaster.render(scene: scene)
        let png = try IndexedPNGEncoder.encode(raster)

        XCTAssertLessThanOrEqual(png.count, RenderProtocol.maximumPayloadBytes)
        let asset = try MapAsset.png(
            data: png,
            expectedWidth: RenderProtocol.viewportWidth,
            expectedHeight: RenderProtocol.viewportHeight
        )
        XCTAssertEqual(asset.width, RenderProtocol.viewportWidth)
        XCTAssertEqual(asset.height, RenderProtocol.viewportHeight)
    }

    func testQuantizesStaticMapToSixteenColorsWithoutChangingItsDimensions() throws {
        let source = try trueColorPNG(width: 159, height: 270)
        let png = try IndexedPNGEncoder.quantize(source, maximumColors: 16)
        let asset = try MapAsset.png(data: png, expectedWidth: 159, expectedHeight: 270)

        XCTAssertEqual(asset.width, 159)
        XCTAssertEqual(asset.height, 270)
        XCTAssertLessThan(png.count, source.count)
        XCTAssertLessThanOrEqual(try decodedColors(png).count, 16)
    }

    private func trueColorPNG(width: Int, height: Int) throws -> Data {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                pixels[offset] = UInt8((x * 255) / width)
                pixels[offset + 1] = UInt8((y * 255) / height)
                pixels[offset + 2] = UInt8(((x + y) * 255) / (width + height))
            }
        }
        return try encodeRGBA(pixels, width: width, height: height)
    }

    private func decodedColors(_ png: Data) throws -> Set<UInt32> {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw IndexedPNGEncoder.Error.imageCreationFailed
        }
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let decoded = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard decoded else { throw IndexedPNGEncoder.Error.imageCreationFailed }
        return Set(stride(from: 0, to: pixels.count, by: 4).map {
            UInt32(pixels[$0]) << 16 | UInt32(pixels[$0 + 1]) << 8 | UInt32(pixels[$0 + 2])
        })
    }

    private func encodeRGBA(_ pixels: [UInt8], width: Int, height: Int) throws -> Data {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else { throw IndexedPNGEncoder.Error.imageCreationFailed }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
            throw IndexedPNGEncoder.Error.destinationCreationFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw IndexedPNGEncoder.Error.encodingFailed }
        return output as Data
    }
}
