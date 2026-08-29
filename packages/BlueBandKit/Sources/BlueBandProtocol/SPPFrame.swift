import Foundation

enum SPPPacketType: UInt8, Sendable {
    case ack = 1
    case sessionConfig = 2
    case data = 3
}

struct SPPFrame: Equatable, Sendable {
    enum Error: Swift.Error, Equatable {
        case invalidMagic
        case invalidLength
        case invalidCRC
        case unknownPacketType
        case payloadTooLarge
    }

    static let headerLength = 8

    let packetType: SPPPacketType
    let sequence: UInt8
    let payload: Data

    func encode() throws -> Data {
        guard payload.count <= Int(UInt16.max) else {
            throw Error.payloadTooLarge
        }

        let length = UInt16(payload.count)
        let crc = CRC16ARC.checksum(payload)
        var output = Data(capacity: Self.headerLength + payload.count)
        output.append(contentsOf: [
            0xA5, 0xA5,
            packetType.rawValue,
            sequence,
            UInt8(truncatingIfNeeded: length),
            UInt8(truncatingIfNeeded: length >> 8),
            UInt8(truncatingIfNeeded: crc),
            UInt8(truncatingIfNeeded: crc >> 8)
        ])
        output.append(payload)
        return output
    }

    static func decode(_ data: Data) throws -> SPPFrame {
        guard data.count >= headerLength else {
            throw Error.invalidLength
        }
        guard data[0] == 0xA5, data[1] == 0xA5 else {
            throw Error.invalidMagic
        }
        guard let packetType = SPPPacketType(rawValue: data[2] & 0x0F) else {
            throw Error.unknownPacketType
        }

        let payloadLength = Int(UInt16(data[4]) | (UInt16(data[5]) << 8))
        guard data.count == headerLength + payloadLength else {
            throw Error.invalidLength
        }

        let expectedCRC = UInt16(data[6]) | (UInt16(data[7]) << 8)
        let payload = data.dropFirst(headerLength)
        guard CRC16ARC.checksum(payload) == expectedCRC else {
            throw Error.invalidCRC
        }

        return SPPFrame(packetType: packetType, sequence: data[3], payload: Data(payload))
    }
}
