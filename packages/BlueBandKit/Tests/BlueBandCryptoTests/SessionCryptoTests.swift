import CryptoSwift
import XCTest
import BlueBandProtocol
@testable import BlueBandCrypto

private struct CryptoSwiftAESBlockCipher: AESBlockCipher {
    func encrypt(block: Data, key: Data) throws -> Data {
        let aes = try AES(key: Array(key), blockMode: ECB(), padding: .noPadding)
        return Data(try aes.encrypt(Array(block)))
    }
}

final class SessionCryptoTests: XCTestCase {
    private let aes = CryptoSwiftAESBlockCipher()
    func testHMACMatchesRFC4231CaseOne() {
        let digest = SessionCrypto.hmacSHA256(
            message: Data("Hi There".utf8),
            key: Data(repeating: 0x0B, count: 20)
        )

        XCTAssertEqual(digest, Data(testHex: """
            b0344c61d8db38535ca8afceaf0bf12b
            881dc200c9833da726e9376c2e32cff7
            """))
    }

    func testHKDFExpandMatchesRFC5869CaseOne() throws {
        let prk = Data(testHex: """
            077709362c2e32df0ddc3f0dc47bba63
            90b6c73bb50f9c3122ec844ad7c2b3e5
            """)
        let info = Data(testHex: "f0f1f2f3f4f5f6f7f8f9")

        let output = try SessionCrypto.hkdfExpand(prk: prk, info: info, outputLength: 42)

        XCTAssertEqual(output, Data(testHex: """
            3cb25f25faacd57a90434f64d0362f2a
            2d2d0a90cf1a5a4c5db02d56ecc4c5bf
            34007208d5b887185865
            """))
    }

    func testSyntheticXiaomiDerivationUsesNonceAsHMACKey() throws {
        let authKey = try AuthKey(bytes: Data((0x00..<0x10).map(UInt8.init)))
        let phone = Data((0x20..<0x30).map(UInt8.init))
        let watch = Data((0x30..<0x40).map(UInt8.init))

        let keys = try SessionCrypto.derive(authKey: authKey, phoneNonce: phone, watchNonce: watch)

        XCTAssertEqual(keys.decryptKey, Data(testHex: "e58c7a55b44ceba4d831383e2e284c08"))
        XCTAssertEqual(keys.encryptKey, Data(testHex: "7a05cade77011d75292b2889496a71b2"))
        XCTAssertEqual(keys.decryptNonce, Data(testHex: "85ba506d"))
        XCTAssertEqual(keys.encryptNonce, Data(testHex: "d77bae53"))
    }

    func testWatchHMACUsesDecryptKeyAndConstantLengthProof() throws {
        let authKey = try AuthKey(bytes: Data((0x00..<0x10).map(UInt8.init)))
        let phone = Data((0x20..<0x30).map(UInt8.init))
        let watch = Data((0x30..<0x40).map(UInt8.init))
        let keys = try SessionCrypto.derive(authKey: authKey, phoneNonce: phone, watchNonce: watch)
        let expected = Data(testHex: "5ed55688fdf9a33795cde8d061d29ef561b2cc15a74ccf0721330afc7315cbe2")

        XCTAssertTrue(SessionCrypto.verifyWatchHMAC(expected, keys: keys, phoneNonce: phone, watchNonce: watch))
        XCTAssertFalse(SessionCrypto.verifyWatchHMAC(Data(repeating: 0, count: 32), keys: keys,
                                                     phoneNonce: phone, watchNonce: watch))
        XCTAssertFalse(SessionCrypto.verifyWatchHMAC(Data(), keys: keys,
                                                     phoneNonce: phone, watchNonce: watch))
    }

    func testCTRMatchesNISTSP80038AFiveOne() throws {
        let key = Data(testHex: "2b7e151628aed2a6abf7158809cf4f3c")
        let counter = Data(testHex: "f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff")
        let plaintext = Data(testHex: """
            6bc1bee22e409f96e93d7e117393172a
            ae2d8a571e03ac9c9eb76fac45af8e51
            """)

        let ciphertext = try SessionCrypto.cryptCTR(plaintext, key: key, initialCounter: counter, cipher: aes)

        XCTAssertEqual(ciphertext, Data(testHex: """
            874d6191b620e3261bef6864990db6ce
            9806f66b7970fdff8617187bb9fffdff
            """))
    }

    func testXiaomiCTRAppliesSameTransformTwice() throws {
        let key = Data(testHex: "00112233445566778899aabbccddeeff")
        let plaintext = Data("partial protobuf payload".utf8)

        let ciphertext = try SessionCrypto.cryptCTR(plaintext, key: key, cipher: aes)
        let restored = try SessionCrypto.cryptCTR(ciphertext, key: key, cipher: aes)

        XCTAssertNotEqual(ciphertext, plaintext)
        XCTAssertEqual(restored, plaintext)
    }

    func testCCMMatchesIndependentAESCCMVectorWithoutAAD() throws {
        let key = Data((0x00..<0x10).map(UInt8.init))
        let nonce = Data((0xA0..<0xAC).map(UInt8.init))
        let plaintext = Data((0x01..<0x22).map(UInt8.init))

        let encrypted = try SessionCrypto.encryptCCM(plaintext, key: key, nonce: nonce, tagLength: 4, cipher: aes)

        XCTAssertEqual(encrypted, Data(testHex: """
            afb16bd5a039cd89dbcc0bf1973ed6f3
            5ae53cdda49dcd1896cd2b10b832f7e5
            0d7b7acba2
            """))
    }

    func testRejectsInvalidCryptoDimensions() {
        XCTAssertThrowsError(try SessionCrypto.cryptCTR(Data([1]), key: Data(count: 15), cipher: aes))
        XCTAssertThrowsError(try SessionCrypto.cryptCTR(Data([1]), key: Data(count: 16),
                                                        initialCounter: Data(count: 15), cipher: aes))
        XCTAssertThrowsError(try SessionCrypto.encryptCCM(Data(), key: Data(count: 16),
                                                          nonce: Data(count: 11), cipher: aes))
        XCTAssertThrowsError(try SessionCrypto.encryptCCM(Data(), key: Data(count: 16),
                                                          nonce: Data(count: 12), tagLength: 3, cipher: aes))
        XCTAssertThrowsError(try SessionCrypto.hkdfExpand(prk: Data([1]), info: Data(),
                                                          outputLength: 8_161))
    }
}
