import Foundation
import BlueBandCrypto

#if canImport(CommonCrypto)
import CommonCrypto

public struct CommonCryptoAESBlockCipher: AESBlockCipher {
    public init() {}

    public func encrypt(block: Data, key: Data) throws -> Data {
        guard key.count == kCCKeySizeAES128 else {
            throw SessionCrypto.Error.invalidKeyLength(key.count)
        }
        guard block.count == kCCBlockSizeAES128 else {
            throw SessionCrypto.Error.invalidBlockLength(block.count)
        }

        let keyBytes = [UInt8](key)
        let input = [UInt8](block)
        var output = [UInt8](repeating: 0, count: kCCBlockSizeAES128)
        let outputCapacity = output.count
        var bytesWritten = 0
        let status = keyBytes.withUnsafeBytes { keyBuffer in
            input.withUnsafeBytes { inputBuffer in
                output.withUnsafeMutableBytes { outputBuffer in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES128),
                        CCOptions(kCCOptionECBMode),
                        keyBuffer.baseAddress,
                        keyBytes.count,
                        nil,
                        inputBuffer.baseAddress,
                        input.count,
                        outputBuffer.baseAddress,
                        outputCapacity,
                        &bytesWritten
                    )
                }
            }
        }
        guard status == kCCSuccess, bytesWritten == kCCBlockSizeAES128 else {
            throw CommonCryptoAESBlockCipherError.failure(status)
        }
        return Data(output)
    }
}

public enum CommonCryptoAESBlockCipherError: Swift.Error, Equatable {
    case failure(CCCryptorStatus)
}
#else
public struct CommonCryptoAESBlockCipher: AESBlockCipher {
    public init() {}

    public func encrypt(block: Data, key: Data) throws -> Data {
        throw CommonCryptoAESBlockCipherError.unsupportedPlatform
    }
}

public enum CommonCryptoAESBlockCipherError: Swift.Error, Equatable {
    case unsupportedPlatform
}
#endif
