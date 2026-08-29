import Foundation

public struct AuthKey: Equatable, Sendable {
    public enum ValidationError: Error, Equatable {
        case invalidLength
        case invalidHex
    }

    public let bytes: Data

    public init(hex: String) throws {
        let normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.utf8.count == 32 else {
            throw ValidationError.invalidLength
        }

        var decoded = Data(capacity: 16)
        var index = normalized.startIndex
        for _ in 0..<16 {
            let next = normalized.index(index, offsetBy: 2)
            guard let byte = UInt8(normalized[index..<next], radix: 16) else {
                throw ValidationError.invalidHex
            }
            decoded.append(byte)
            index = next
        }

        bytes = decoded
    }

    public init(bytes: Data) throws {
        guard bytes.count == 16 else {
            throw ValidationError.invalidLength
        }
        self.bytes = bytes
    }
}
