import Foundation

struct BandCommand: Equatable, Sendable {
    enum Error: Swift.Error, Equatable {
        case missingType
        case missingSubtype
        case integerOutOfRange
    }

    let type: UInt32
    let subtype: UInt32
    let bodyField: Int?
    let body: Data?
    let status: UInt32?

    init(type: UInt32, subtype: UInt32, bodyField: Int? = nil, body: Data? = nil, status: UInt32? = nil) {
        self.type = type
        self.subtype = subtype
        self.bodyField = bodyField
        self.body = body
        self.status = status
    }

    func encode() -> Data {
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

    static func decode(_ data: Data) throws -> BandCommand {
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

struct WatchNonce: Equatable, Sendable {
    let nonce: Data
    let hmac: Data
}

enum BandCommands {
    enum Error: Swift.Error, Equatable {
        case unexpectedCommand
        case missingField
        case invalidNonceLength
        case invalidHMACLength
    }

    static func phoneNonce(_ nonce: Data) -> BandCommand {
        var phoneNonce = ProtoWriter()
        phoneNonce.putBytes(field: 1, value: nonce)

        var auth = ProtoWriter()
        auth.putBytes(field: 30, value: phoneNonce.data)
        return BandCommand(type: 1, subtype: 26, bodyField: 3, body: auth.data)
    }

    static func authStep3(encryptedNonces: Data, encryptedDeviceInfo: Data) -> BandCommand {
        var step3 = ProtoWriter()
        step3.putBytes(field: 1, value: encryptedNonces)
        step3.putBytes(field: 2, value: encryptedDeviceInfo)

        var auth = ProtoWriter()
        auth.putBytes(field: 32, value: step3.data)
        return BandCommand(type: 1, subtype: 27, bodyField: 3, body: auth.data)
    }

    static let batteryRequest = BandCommand(type: 2, subtype: 1)
    static let deviceInfoRequest = BandCommand(type: 2, subtype: 2)
    static let deviceStateRequest = BandCommand(type: 2, subtype: 78)

    static func authDeviceInfo(apiLevel: Float, phoneName: String, region: String) -> Data {
        var info = ProtoWriter()
        info.putVarint(field: 1, value: 1)
        info.putFixed32(field: 2, value: apiLevel.bitPattern)
        info.putString(field: 3, value: phoneName)
        info.putVarint(field: 4, value: UInt64(UInt32.max))
        info.putString(field: 5, value: region.uppercased())
        return info.data
    }

    static func authStatus(_ command: BandCommand) throws -> UInt32? {
        if let status = command.status { return status }
        guard command.bodyField == 3, let body = command.body else { return nil }
        let raw = try ProtoReader(data: body).allFields().firstVarint(field: 8)
        guard let raw else { return nil }
        guard raw <= UInt64(UInt32.max) else { throw BandCommand.Error.integerOutOfRange }
        return UInt32(raw)
    }

    static func parseWatchNonce(_ command: BandCommand) throws -> WatchNonce {
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

struct BandBattery: Equatable, Sendable {
    enum Error: Swift.Error, Equatable {
        case unexpectedCommand
        case missingLevel
        case integerOutOfRange
    }

    let level: UInt8
    let state: UInt32?

    static func decode(_ command: BandCommand) throws -> BandBattery {
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

struct BandDeviceInfo: Equatable, Sendable {
    enum Error: Swift.Error, Equatable {
        case unexpectedCommand
        case invalidText
    }

    let serial: String?
    let firmware: String?
    let model: String?

    static func decode(_ command: BandCommand) throws -> BandDeviceInfo {
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
