import Foundation
import BlueBandProtocol

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

public protocol AESBlockCipher: Sendable {
    func encrypt(block: Data, key: Data) throws -> Data
}

public struct SessionKeys: Equatable, Sendable {
    public let decryptKey: Data
    public let encryptKey: Data
    public let decryptNonce: Data
    public let encryptNonce: Data

    public init(decryptKey: Data, encryptKey: Data, decryptNonce: Data, encryptNonce: Data) {
        self.decryptKey = decryptKey
        self.encryptKey = encryptKey
        self.decryptNonce = decryptNonce
        self.encryptNonce = encryptNonce
    }
}

public enum SessionCrypto {
    public enum Error: Swift.Error, Equatable {
        case invalidKeyLength(Int)
        case invalidNonceLength(Int)
        case invalidCounterLength(Int)
        case invalidTagLength(Int)
        case invalidOutputLength(Int)
        case invalidBlockLength(Int)
        case messageTooLong(Int)
    }

    private static let aesBlockSize = 16
    private static let aes128KeySize = 16

    public static func hmacSHA256(message: Data, key: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: symmetricKey))
    }

    public static func hkdfExpand(prk: Data, info: Data, outputLength: Int) throws -> Data {
        guard outputLength >= 0, outputLength <= 255 * 32 else {
            throw Error.invalidOutputLength(outputLength)
        }
        var output = Data(capacity: outputLength)
        var previous = Data()
        var counter: UInt8 = 1
        while output.count < outputLength {
            previous = hmacSHA256(message: previous + info + Data([counter]), key: prk)
            output.append(previous)
            counter &+= 1
        }
        return Data(output.prefix(outputLength))
    }

    public static func derive(authKey: AuthKey, phoneNonce: Data, watchNonce: Data) throws -> SessionKeys {
        guard phoneNonce.count == 16 else { throw Error.invalidNonceLength(phoneNonce.count) }
        guard watchNonce.count == 16 else { throw Error.invalidNonceLength(watchNonce.count) }

        let prk = hmacSHA256(message: authKey.bytes, key: phoneNonce + watchNonce)
        let expanded = try hkdfExpand(
            prk: prk,
            info: Data("miwear-auth".utf8),
            outputLength: 64
        )
        return SessionKeys(
            decryptKey: Data(expanded[0..<16]),
            encryptKey: Data(expanded[16..<32]),
            decryptNonce: Data(expanded[32..<36]),
            encryptNonce: Data(expanded[36..<40])
        )
    }

    public static func verifyWatchHMAC(
        _ received: Data,
        keys: SessionKeys,
        phoneNonce: Data,
        watchNonce: Data
    ) -> Bool {
        let expected = hmacSHA256(message: watchNonce + phoneNonce, key: keys.decryptKey)
        return constantTimeEqual(received, expected)
    }

    public static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) {
            difference |= left ^ right
        }
        return difference == 0
    }

    public static func cryptCTR(
        _ data: Data,
        key: Data,
        cipher: any AESBlockCipher
    ) throws -> Data {
        try cryptCTR(data, key: key, initialCounter: key, cipher: cipher)
    }

    public static func cryptCTR(
        _ data: Data,
        key: Data,
        initialCounter: Data,
        cipher: any AESBlockCipher
    ) throws -> Data {
        guard key.count == aes128KeySize else { throw Error.invalidKeyLength(key.count) }
        guard initialCounter.count == aesBlockSize else {
            throw Error.invalidCounterLength(initialCounter.count)
        }

        let input = [UInt8](data)
        var counter = [UInt8](initialCounter)
        var output = [UInt8](repeating: 0, count: input.count)
        var offset = 0
        while offset < input.count {
            let stream = [UInt8](try encryptBlock(Data(counter), key: key, cipher: cipher))
            let count = min(aesBlockSize, input.count - offset)
            for index in 0..<count {
                output[offset + index] = input[offset + index] ^ stream[index]
            }
            incrementBigEndian(&counter)
            offset += count
        }
        return Data(output)
    }

    public static func encryptCCM(
        _ plaintext: Data,
        key: Data,
        nonce: Data,
        tagLength: Int = 4,
        cipher: any AESBlockCipher
    ) throws -> Data {
        guard key.count == aes128KeySize else { throw Error.invalidKeyLength(key.count) }
        guard nonce.count == 12 else { throw Error.invalidNonceLength(nonce.count) }
        guard (4...16).contains(tagLength), tagLength.isMultiple(of: 2) else {
            throw Error.invalidTagLength(tagLength)
        }

        let lengthFieldBytes = 15 - nonce.count
        let maximumMessageLength = 1 << (8 * lengthFieldBytes)
        guard plaintext.count < maximumMessageLength else {
            throw Error.messageTooLong(plaintext.count)
        }

        let flags = UInt8(((tagLength - 2) / 2) << 3) | UInt8(lengthFieldBytes - 1)
        let b0 = Data([flags]) + nonce + encodeBigEndian(plaintext.count, byteCount: lengthFieldBytes)

        var mac = Data(repeating: 0, count: aesBlockSize)
        mac = try encryptBlock(xorBlock(mac, b0), key: key, cipher: cipher)
        var offset = 0
        while offset < plaintext.count {
            let count = min(aesBlockSize, plaintext.count - offset)
            var block = Data(repeating: 0, count: aesBlockSize)
            block.replaceSubrange(0..<count, with: plaintext[offset..<(offset + count)])
            mac = try encryptBlock(xorBlock(mac, block), key: key, cipher: cipher)
            offset += count
        }

        let s0 = try encryptBlock(
            counterBlock(nonce: nonce, counter: 0, lengthFieldBytes: lengthFieldBytes),
            key: key,
            cipher: cipher
        )
        var tag = Data(capacity: tagLength)
        for index in 0..<tagLength {
            tag.append(mac[index] ^ s0[index])
        }

        let input = [UInt8](plaintext)
        var ciphertext = [UInt8](repeating: 0, count: input.count)
        offset = 0
        var counter = 1
        while offset < input.count {
            let stream = [UInt8](try encryptBlock(
                counterBlock(nonce: nonce, counter: counter, lengthFieldBytes: lengthFieldBytes),
                key: key,
                cipher: cipher
            ))
            let count = min(aesBlockSize, input.count - offset)
            for index in 0..<count {
                ciphertext[offset + index] = input[offset + index] ^ stream[index]
            }
            offset += count
            counter += 1
        }
        return Data(ciphertext) + tag
    }

    private static func encryptBlock(
        _ block: Data,
        key: Data,
        cipher: any AESBlockCipher
    ) throws -> Data {
        guard key.count == aes128KeySize else { throw Error.invalidKeyLength(key.count) }
        guard block.count == aesBlockSize else { throw Error.invalidBlockLength(block.count) }
        let encrypted = try cipher.encrypt(block: block, key: key)
        guard encrypted.count == aesBlockSize else { throw Error.invalidBlockLength(encrypted.count) }
        return encrypted
    }

    private static func incrementBigEndian(_ value: inout [UInt8]) {
        for index in value.indices.reversed() {
            value[index] &+= 1
            if value[index] != 0 { return }
        }
    }

    private static func counterBlock(nonce: Data, counter: Int, lengthFieldBytes: Int) -> Data {
        Data([UInt8(lengthFieldBytes - 1)])
            + nonce
            + encodeBigEndian(counter, byteCount: lengthFieldBytes)
    }

    private static func encodeBigEndian(_ value: Int, byteCount: Int) -> Data {
        var output = [UInt8](repeating: 0, count: byteCount)
        var remaining = value
        for index in output.indices.reversed() {
            output[index] = UInt8(truncatingIfNeeded: remaining)
            remaining >>= 8
        }
        return Data(output)
    }

    private static func xorBlock(_ lhs: Data, _ rhs: Data) -> Data {
        precondition(lhs.count == aesBlockSize && rhs.count == aesBlockSize)
        return Data(zip(lhs, rhs).map { $0.0 ^ $0.1 })
    }
}
