import Foundation

public struct SPPReassembler: Sendable {
    private static let maximumRetainedBytes = Int(UInt16.max) + SPPFrame.headerLength
    private var buffer = Data()

    public init() {}

    public mutating func append(_ bytes: Data) -> [SPPFrame] {
        buffer.append(bytes)
        buffer = Data(buffer)
        var frames: [SPPFrame] = []

        while true {
            guard buffer.count >= 2 else {
                return frames
            }

            guard let magicOffset = firstMagicOffset() else {
                let retainMagicPrefix = buffer.last == 0xA5
                buffer = retainMagicPrefix ? Data([0xA5]) : Data()
                return frames
            }
            if magicOffset > 0 {
                discardPrefix(magicOffset)
            }

            guard buffer.count >= SPPFrame.headerLength else {
                return frames
            }

            guard SPPPacketType(rawValue: byte(at: 2) & 0x0F) != nil else {
                discardPrefix(1)
                continue
            }

            let payloadLength = Int(UInt16(byte(at: 4)) | (UInt16(byte(at: 5)) << 8))
            let frameLength = SPPFrame.headerLength + payloadLength
            guard buffer.count >= frameLength else {
                if buffer.count > Self.maximumRetainedBytes {
                    buffer = Data(buffer.suffix(Self.maximumRetainedBytes))
                }
                return frames
            }

            let candidate = Data(buffer.prefix(frameLength))
            do {
                frames.append(try SPPFrame.decode(candidate))
                discardPrefix(frameLength)
            } catch {
                discardPrefix(1)
            }
        }
    }

    private func firstMagicOffset() -> Int? {
        guard buffer.count >= 2 else { return nil }
        for offset in 0..<(buffer.count - 1) where byte(at: offset) == 0xA5 && byte(at: offset + 1) == 0xA5 {
            return offset
        }
        return nil
    }

    private func byte(at offset: Int) -> UInt8 {
        buffer[buffer.index(buffer.startIndex, offsetBy: offset)]
    }

    private mutating func discardPrefix(_ count: Int) {
        buffer = Data(buffer.dropFirst(count))
    }
}
