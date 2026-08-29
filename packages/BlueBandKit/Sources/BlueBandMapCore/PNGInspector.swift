import Foundation

internal enum PNGInspector {
    enum Error: Swift.Error, Equatable {
        case truncated
        case invalidSignature
        case missingIHDR
    }

    static func dimensions(of data: Data) throws -> (width: Int, height: Int) {
        guard data.count >= 24 else {
            throw Error.truncated
        }

        let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        guard Array(data[0..<8]) == signature else {
            throw Error.invalidSignature
        }

        guard Array(data[12..<16]) == Array("IHDR".utf8) else {
            throw Error.missingIHDR
        }

        let width = readUInt32(from: data, at: 16)
        let height = readUInt32(from: data, at: 20)
        return (Int(width), Int(height))
    }

    private static func readUInt32(from data: Data, at offset: Int) -> UInt32 {
        data[offset..<(offset + 4)].reduce(UInt32(0)) { value, byte in
            (value << 8) | UInt32(byte)
        }
    }
}
