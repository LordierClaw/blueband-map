import Foundation

enum ProtoField: Equatable, Sendable {
    case varint(number: Int, value: UInt64)
    case fixed32(number: Int, value: UInt32)
    case fixed64(number: Int, value: UInt64)
    case bytes(number: Int, value: Data)
}

struct ProtoWriter {
    private(set) var data = Data()

    mutating func putVarint(field: Int, value: UInt64) {
        putKey(field: field, wireType: 0)
        appendVarint(value)
    }

    mutating func putBytes(field: Int, value: Data) {
        putKey(field: field, wireType: 2)
        appendVarint(UInt64(value.count))
        data.append(value)
    }

    mutating func putString(field: Int, value: String) {
        putBytes(field: field, value: Data(value.utf8))
    }

    mutating func putFixed32(field: Int, value: UInt32) {
        putKey(field: field, wireType: 5)
        for shift in stride(from: 0, to: 32, by: 8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }

    mutating func putFixed64(field: Int, value: UInt64) {
        putKey(field: field, wireType: 1)
        for shift in stride(from: 0, to: 64, by: 8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
    }

    private mutating func putKey(field: Int, wireType: UInt64) {
        precondition(field > 0)
        appendVarint((UInt64(field) << 3) | wireType)
    }

    private mutating func appendVarint(_ value: UInt64) {
        var remaining = value
        while remaining >= 0x80 {
            data.append(UInt8(truncatingIfNeeded: remaining) | 0x80)
            remaining >>= 7
        }
        data.append(UInt8(remaining))
    }
}

struct ProtoReader {
    enum Error: Swift.Error, Equatable {
        case truncated
        case invalidFieldNumber
        case invalidLength
        case varintOverflow
        case unsupportedWireType(UInt8)
    }

    let data: Data

    func allFields() throws -> [ProtoField] {
        var cursor = Cursor(data: data)
        var fields: [ProtoField] = []
        while !cursor.isAtEnd {
            let key = try cursor.readVarint()
            let numberValue = key >> 3
            guard numberValue > 0, numberValue <= UInt64(Int.max) else {
                throw Error.invalidFieldNumber
            }
            let number = Int(numberValue)
            let wireType = UInt8(key & 0x07)

            switch wireType {
            case 0:
                fields.append(.varint(number: number, value: try cursor.readVarint()))
            case 1:
                fields.append(.fixed64(number: number, value: try cursor.readFixed64()))
            case 2:
                fields.append(.bytes(number: number, value: try cursor.readBytes()))
            case 5:
                fields.append(.fixed32(number: number, value: try cursor.readFixed32()))
            default:
                throw Error.unsupportedWireType(wireType)
            }
        }
        return fields
    }

    private struct Cursor {
        let data: Data
        var offset = 0

        var isAtEnd: Bool { offset == data.count }

        mutating func readVarint() throws -> UInt64 {
            var value: UInt64 = 0
            for byteIndex in 0..<10 {
                let byte = try readByte()
                if byteIndex == 9, byte > 1 {
                    throw Error.varintOverflow
                }
                value |= UInt64(byte & 0x7F) << UInt64(byteIndex * 7)
                if (byte & 0x80) == 0 {
                    return value
                }
            }
            throw Error.varintOverflow
        }

        mutating func readBytes() throws -> Data {
            let rawLength = try readVarint()
            guard rawLength <= UInt64(Int.max) else {
                throw Error.invalidLength
            }
            let length = Int(rawLength)
            guard length <= data.count - offset else {
                throw Error.truncated
            }
            defer { offset += length }
            return Data(data[offset..<(offset + length)])
        }

        mutating func readFixed32() throws -> UInt32 {
            guard data.count - offset >= 4 else { throw Error.truncated }
            var value: UInt32 = 0
            for index in 0..<4 {
                value |= UInt32(data[offset + index]) << UInt32(index * 8)
            }
            offset += 4
            return value
        }

        mutating func readFixed64() throws -> UInt64 {
            guard data.count - offset >= 8 else { throw Error.truncated }
            var value: UInt64 = 0
            for index in 0..<8 {
                value |= UInt64(data[offset + index]) << UInt64(index * 8)
            }
            offset += 8
            return value
        }

        private mutating func readByte() throws -> UInt8 {
            guard offset < data.count else { throw Error.truncated }
            defer { offset += 1 }
            return data[offset]
        }
    }
}

extension Array where Element == ProtoField {
    func firstVarint(field number: Int) -> UInt64? {
        for case let .varint(fieldNumber, value) in self where fieldNumber == number {
            return value
        }
        return nil
    }

    func firstBytes(field number: Int) -> Data? {
        for case let .bytes(fieldNumber, value) in self where fieldNumber == number {
            return value
        }
        return nil
    }
}
