# Third-Party Notices

This repository is derived from protocol behavior and independent public evidence listed in the approved design. Reference implementations are not linked into the runtime unless explicitly listed here.

Runtime and test dependencies, their pinned versions, roles, and required notices are added with the implementation that introduces them.

The protocol laboratory is a clean, narrow implementation based on behavior documented in the BlueBand POC. Its provenance and fixed reference revisions are recorded in the approved design and its `CAPTURE.md` file.

## swift-crypto 4.5.1

Apple's Apache-2.0-licensed Swift Crypto package supplies CryptoKit-compatible HMAC and SHA-256 behavior on Linux and re-exports CryptoKit on Apple platforms. Its license and notices are distributed by Swift Package Manager with the dependency source.

## CryptoSwift 1.10.0

CryptoSwift is used only by `BlueBandCryptoTests` as an independent Linux AES block provider. It is not linked into the iOS application. CryptoSwift requires retention of its license and the following acknowledgement: This product includes software developed by Marcin Krzyzanowski (https://krzyzanowskim.com/).
