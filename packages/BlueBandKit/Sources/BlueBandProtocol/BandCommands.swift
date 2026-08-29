import Foundation

public struct BandCommand: Equatable, Sendable {
    public enum Error: Swift.Error, Equatable {
        case missingType
        case missingSubtype
        case integerOutOfRange
    }

    public let type: UInt32
    public let subtype: UInt32
    public let bodyField: Int?
    public let body: Data?
    public let status: UInt32?

    public init(type: UInt32, subtype: UInt32, bodyField: Int? = nil, body: Data? = nil, status: UInt32? = nil) {
        self.type = type
        self.subtype = subtype
        self.bodyField = bodyField
        self.body = body
        self.status = status
    }

    public func encode() -> Data {
        var writer = ProtoWriter()
        writer.putVarint(field: 1, value: UInt64(type))
        writer.putVarint(field: 2, value: UInt64(subtype))
        if let bodyField, let body {
            writer.putBytes(field: bodyField, value: body)
        }
        if let status {
            writer.putVarint(field: 100, value: UInt64(status))
        }
        return writer.data
    }

    public static func decode(_ data: Data) throws -> BandCommand {
        let fields = try ProtoReader(data: data).allFields()
        guard let rawType = fields.firstVarint(field: 1) else { throw Error.missingType }
        guard let rawSubtype = fields.firstVarint(field: 2) else { throw Error.missingSubtype }
        guard rawType <= UInt64(UInt32.max), rawSubtype <= UInt64(UInt32.max) else {
            throw Error.integerOutOfRange
        }

        let bodyEntry = fields.compactMap { field -> (Int, Data)? in
            guard case let .bytes(number, value) = field else { return nil }
            return (number, value)
        }.first
        let rawStatus = fields.firstVarint(field: 100)
        if let rawStatus, rawStatus > UInt64(UInt32.max) {
            throw Error.integerOutOfRange
        }

        return BandCommand(
            type: UInt32(rawType),
            subtype: UInt32(rawSubtype),
            bodyField: bodyEntry?.0,
            body: bodyEntry?.1,
            status: rawStatus.map { UInt32($0) }
        )
    }
}

public struct WatchNonce: Equatable, Sendable {
    public let nonce: Data
    public let hmac: Data
}

public enum BandCommands {
    public enum Error: Swift.Error, Equatable {
        case unexpectedCommand
        case missingField
        case invalidNonceLength
        case invalidHMACLength
    }

    public static func phoneNonce(_ nonce: Data) -> BandCommand {
        var phoneNonce = ProtoWriter()
        phoneNonce.putBytes(field: 1, value: nonce)

        var auth = ProtoWriter()
        auth.putBytes(field: 30, value: phoneNonce.data)
        return BandCommand(type: 1, subtype: 26, bodyField: 3, body: auth.data)
    }

    public static func authStep3(encryptedNonces: Data, encryptedDeviceInfo: Data) -> BandCommand {
        var step3 = ProtoWriter()
        step3.putBytes(field: 1, value: encryptedNonces)
        step3.putBytes(field: 2, value: encryptedDeviceInfo)

        var auth = ProtoWriter()
        auth.putBytes(field: 32, value: step3.data)
        return BandCommand(type: 1, subtype: 27, bodyField: 3, body: auth.data)
    }

    public static let batteryRequest = BandCommand(type: 2, subtype: 1)
    public static let deviceInfoRequest = BandCommand(type: 2, subtype: 2)
    public static let deviceStateRequest = BandCommand(type: 2, subtype: 78)

    public static func authDeviceInfo(apiLevel: Float, phoneName: String, region: String) -> Data {
        var info = ProtoWriter()
        info.putVarint(field: 1, value: 1)
        info.putFixed32(field: 2, value: apiLevel.bitPattern)
        info.putString(field: 3, value: phoneName)
        info.putVarint(field: 4, value: UInt64(UInt32.max))
        info.putString(field: 5, value: region.uppercased())
        return info.data
    }

    public static func authStatus(_ command: BandCommand) throws -> UInt32? {
        if let status = command.status { return status }
        guard command.bodyField == 3, let body = command.body else { return nil }
        let raw = try ProtoReader(data: body).allFields().firstVarint(field: 8)
        guard let raw else { return nil }
        guard raw <= UInt64(UInt32.max) else { throw BandCommand.Error.integerOutOfRange }
        return UInt32(raw)
    }

    public static func parseWatchNonce(_ command: BandCommand) throws -> WatchNonce {
        guard command.type == 1, command.subtype == 26, command.bodyField == 3,
              let authBytes = command.body else {
            throw Error.unexpectedCommand
        }
        let auth = try ProtoReader(data: authBytes).allFields()
        guard let watchBytes = auth.firstBytes(field: 31) else { throw Error.missingField }
        let watch = try ProtoReader(data: watchBytes).allFields()
        guard let nonce = watch.firstBytes(field: 1) else { throw Error.missingField }
        guard let hmac = watch.firstBytes(field: 2) else { throw Error.missingField }
        guard nonce.count == 16 else { throw Error.invalidNonceLength }
        guard hmac.count == 32 else { throw Error.invalidHMACLength }
        return WatchNonce(nonce: nonce, hmac: hmac)
    }
}

public struct BandBattery: Equatable, Sendable {
    public enum Error: Swift.Error, Equatable {
        case unexpectedCommand
        case missingLevel
        case integerOutOfRange
    }

    public let level: UInt8
    public let state: UInt32?

    public static func decode(_ command: BandCommand) throws -> BandBattery {
        guard command.type == 2, command.subtype == 1, command.bodyField == 4,
              let systemBytes = command.body else {
            throw Error.unexpectedCommand
        }
        let system = try ProtoReader(data: systemBytes).allFields()
        guard let powerBytes = system.firstBytes(field: 2) else { throw Error.missingLevel }
        let power = try ProtoReader(data: powerBytes).allFields()
        guard let batteryBytes = power.firstBytes(field: 1) else { throw Error.missingLevel }
        let battery = try ProtoReader(data: batteryBytes).allFields()
        guard let rawLevel = battery.firstVarint(field: 1) else { throw Error.missingLevel }
        let rawState = battery.firstVarint(field: 2)
        guard rawLevel <= UInt64(UInt8.max), rawState.map({ $0 <= UInt64(UInt32.max) }) ?? true else {
            throw Error.integerOutOfRange
        }
        return BandBattery(level: UInt8(rawLevel), state: rawState.map { UInt32($0) })
    }
}

public struct BandDeviceInfo: Equatable, Sendable {
    public enum Error: Swift.Error, Equatable {
        case unexpectedCommand
        case invalidText
    }

    public let serial: String?
    public let firmware: String?
    public let model: String?

    public static func decode(_ command: BandCommand) throws -> BandDeviceInfo {
        guard command.type == 2, command.subtype == 2, command.bodyField == 4,
              let systemBytes = command.body else {
            throw Error.unexpectedCommand
        }
        let system = try ProtoReader(data: systemBytes).allFields()
        guard let infoBytes = system.firstBytes(field: 3) else {
            return BandDeviceInfo(serial: nil, firmware: nil, model: nil)
        }
        let info = try ProtoReader(data: infoBytes).allFields()
        return BandDeviceInfo(
            serial: try decodeText(info.firstBytes(field: 1)),
            firmware: try decodeText(info.firstBytes(field: 2)),
            model: try decodeText(info.firstBytes(field: 4))
        )
    }

    private static func decodeText(_ data: Data?) throws -> String? {
        guard let data else { return nil }
        guard let value = String(data: data, encoding: .utf8) else { throw Error.invalidText }
        return value
    }
}
