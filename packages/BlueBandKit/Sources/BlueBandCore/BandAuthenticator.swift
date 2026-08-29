import Foundation
import BlueBandCrypto
import BlueBandProtocol

public struct AuthDeviceDescriptor: Equatable, Sendable {
    public let apiLevel: Float
    public let phoneName: String
    public let region: String

    public init(apiLevel: Float, phoneName: String, region: String) {
        self.apiLevel = apiLevel
        self.phoneName = phoneName
        self.region = region
    }

    public static var current: Self {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let localeRegion = Locale.current.region?.identifier.uppercased() ?? "US"
        return Self(
            apiLevel: Float(version.majorVersion),
            phoneName: "BlueBandMap iPhone",
            region: localeRegion.count == 2 ? localeRegion : "US"
        )
    }
}

public struct AuthenticationResult: Equatable, Sendable {
    public let keys: SessionKeys
    public init(keys: SessionKeys) { self.keys = keys }
}

public enum BandAuthenticationError: Swift.Error, Equatable {
    case randomGenerationFailed
    case invalidPhoneNonce
    case hmacMismatch
    case rejected(status: UInt32)
    case disconnected
    case timeout
}

public struct BandAuthenticator: Sendable {
    public typealias NonceGenerator = @Sendable () throws -> Data

    public let timeout: Duration
    public let nonceGenerator: NonceGenerator
    public let device: AuthDeviceDescriptor
    private let cipher: any AESBlockCipher

    public init(
        timeout: Duration = .seconds(10),
        nonceGenerator: NonceGenerator? = nil,
        device: AuthDeviceDescriptor = .current,
        cipher: any AESBlockCipher
    ) {
        self.timeout = timeout
        self.nonceGenerator = nonceGenerator ?? { BandAuthenticator.randomNonce() }
        self.device = device
        self.cipher = cipher
    }

    public func authenticate(authKey: AuthKey, transport: any BandTransportProtocol) async throws -> AuthenticationResult {
        do {
            return try await withThrowingTaskGroup(of: AuthenticationResult.self) { group in
                group.addTask { [self] in try await runExchange(authKey: authKey, transport: transport) }
                group.addTask { [timeout] in
                    try await Task.sleep(for: timeout)
                    throw BandAuthenticationError.timeout
                }
                guard let result = try await group.next() else { throw BandAuthenticationError.disconnected }
                group.cancelAll()
                return result
            }
        } catch {
            await transport.close()
            throw error
        }
    }

    private func runExchange(authKey: AuthKey, transport: any BandTransportProtocol) async throws -> AuthenticationResult {
        try await transport.configure()
        var iterator = await transport.incoming().makeAsyncIterator()
        let phoneNonce = try nonceGenerator()
        guard phoneNonce.count == 16 else { throw BandAuthenticationError.invalidPhoneNonce }
        try await transport.send(channel: 1, opcode: 1, body: BandCommands.phoneNonce(phoneNonce).encode())

        let watch = try await nextWatchNonce(from: &iterator)
        let keys = try SessionCrypto.derive(authKey: authKey, phoneNonce: phoneNonce, watchNonce: watch.nonce)
        guard SessionCrypto.verifyWatchHMAC(watch.hmac, keys: keys, phoneNonce: phoneNonce, watchNonce: watch.nonce) else {
            throw BandAuthenticationError.hmacMismatch
        }

        let proof = SessionCrypto.hmacSHA256(message: phoneNonce + watch.nonce, key: keys.encryptKey)
        let info = BandCommands.authDeviceInfo(apiLevel: device.apiLevel, phoneName: device.phoneName, region: device.region)
        let encryptedInfo = try SessionCrypto.encryptCCM(
            info,
            key: keys.encryptKey,
            nonce: keys.encryptNonce + Data(repeating: 0, count: 8),
            tagLength: 4,
            cipher: cipher
        )
        try await transport.send(
            channel: 1,
            opcode: 1,
            body: BandCommands.authStep3(encryptedNonces: proof, encryptedDeviceInfo: encryptedInfo).encode()
        )
        try await waitForSuccess(from: &iterator)
        return AuthenticationResult(keys: keys)
    }

    private func nextWatchNonce(
        from iterator: inout AsyncThrowingStream<BandTransportMessage, Swift.Error>.AsyncIterator
    ) async throws -> WatchNonce {
        while let message = try await iterator.next() {
            guard message.channel == 1, message.opcode == 1,
                  let command = try? BandCommand.decode(message.body),
                  command.type == 1, command.subtype == 26 else { continue }
            return try BandCommands.parseWatchNonce(command)
        }
        throw BandAuthenticationError.disconnected
    }

    private func waitForSuccess(
        from iterator: inout AsyncThrowingStream<BandTransportMessage, Swift.Error>.AsyncIterator
    ) async throws {
        while let message = try await iterator.next() {
            guard message.channel == 1, message.opcode == 1,
                  let command = try? BandCommand.decode(message.body),
                  command.type == 1, command.subtype == 27 else { continue }
            if let status = try BandCommands.authStatus(command), status != 0 {
                throw BandAuthenticationError.rejected(status: status)
            }
            return
        }
        throw BandAuthenticationError.disconnected
    }

    private static func randomNonce() -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<16).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}
