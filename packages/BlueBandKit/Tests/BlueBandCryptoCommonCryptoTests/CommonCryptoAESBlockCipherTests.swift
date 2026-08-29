import Foundation
import XCTest
import BlueBandCryptoCommonCrypto

#if canImport(CommonCrypto)
final class CommonCryptoAESBlockCipherTests: XCTestCase {
    func testEncryptsNISTAES128Block() throws {
        let cipher = CommonCryptoAESBlockCipher()
        let encrypted = try cipher.encrypt(
            block: Data(hex: "00112233445566778899aabbccddeeff"),
            key: Data(hex: "000102030405060708090a0b0c0d0e0f")
        )
        XCTAssertEqual(encrypted, Data(hex: "69c4e0d86a7b0430d8cdb78070b4c55a"))
    }
}

private extension Data {
    init(hex: String) {
        self.init(stride(from: 0, to: hex.count, by: 2).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
        })
    }
}
#endif
