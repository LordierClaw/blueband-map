import Foundation

public struct ThirdPartyAppIdentity: Equatable, Sendable {
    public let packageName: String
    public let fingerprint: Data

    public init(packageName: String, fingerprint: Data) {
        self.packageName = packageName
        self.fingerprint = fingerprint
    }
}

public enum ThirdPartyAppPacket: Equatable, Sendable {
    case statusRequest(ThirdPartyAppIdentity)
    case wearMessage(identity: ThirdPartyAppIdentity, content: Data)
}

public enum ThirdPartyAppCodec {
    public enum Error: Swift.Error, Equatable {
        case unexpectedCommand
        case missingField
        case invalidPackage
        case invalidFingerprint
    }

    public static func decode(_ command: BandCommand) throws -> ThirdPartyAppPacket {
        guard command.type == 20, command.bodyField == 22, let body = command.body else {
            throw Error.unexpectedCommand
        }
        let fields = try ProtoReader(data: body).allFields()
        switch command.subtype {
        case 6:
            guard let basicInfo = fields.firstBytes(field: 5) else { throw Error.missingField }
            return .statusRequest(try decodeIdentity(basicInfo))
        case 9:
            guard let rawMessage = fields.firstBytes(field: 9) else { throw Error.missingField }
            let message = try ProtoReader(data: rawMessage).allFields()
            guard let basicInfo = message.firstBytes(field: 1),
                  let content = message.firstBytes(field: 2) else {
                throw Error.missingField
            }
            return .wearMessage(identity: try decodeIdentity(basicInfo), content: content)
        default:
            throw Error.unexpectedCommand
        }
    }

    public static func status(identity: ThirdPartyAppIdentity, connected: Bool) -> BandCommand {
        var phoneStatus = ProtoWriter()
        phoneStatus.putBytes(field: 1, value: encodeIdentity(identity))
        phoneStatus.putVarint(field: 2, value: connected ? 1 : 2)

        var thirdPartyApp = ProtoWriter()
        thirdPartyApp.putBytes(field: 8, value: phoneStatus.data)
        return BandCommand(type: 20, subtype: 7, bodyField: 22, body: thirdPartyApp.data)
    }

    public static func phoneMessage(identity: ThirdPartyAppIdentity, content: Data) -> BandCommand {
        var message = ProtoWriter()
        message.putBytes(field: 1, value: encodeIdentity(identity))
        message.putBytes(field: 2, value: content)

        var thirdPartyApp = ProtoWriter()
        thirdPartyApp.putBytes(field: 9, value: message.data)
        return BandCommand(type: 20, subtype: 8, bodyField: 22, body: thirdPartyApp.data)
    }

    private static func encodeIdentity(_ identity: ThirdPartyAppIdentity) -> Data {
        var writer = ProtoWriter()
        writer.putString(field: 1, value: identity.packageName)
        writer.putBytes(field: 2, value: identity.fingerprint)
        return writer.data
    }

    private static func decodeIdentity(_ data: Data) throws -> ThirdPartyAppIdentity {
        let fields = try ProtoReader(data: data).allFields()
        guard let packageData = fields.firstBytes(field: 1),
              let packageName = String(data: packageData, encoding: .utf8),
              !packageName.isEmpty else {
            throw Error.invalidPackage
        }
        guard let fingerprint = fields.firstBytes(field: 2), !fingerprint.isEmpty else {
            throw Error.invalidFingerprint
        }
        return ThirdPartyAppIdentity(packageName: packageName, fingerprint: fingerprint)
    }
}
