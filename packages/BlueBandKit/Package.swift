// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BlueBandKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "BlueBandProtocol", targets: ["BlueBandProtocol"]),
        .library(name: "BlueBandCrypto", targets: ["BlueBandCrypto"]),
        .library(name: "BlueBandCryptoCommonCrypto", targets: ["BlueBandCryptoCommonCrypto"]),
        .library(name: "BlueBandCore", targets: ["BlueBandCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.5.1"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", exact: "1.10.0"),
    ],
    targets: [
        .target(name: "BlueBandProtocol"),
        .target(
            name: "BlueBandCrypto",
            dependencies: [
                "BlueBandProtocol",
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
        .target(
            name: "BlueBandCryptoCommonCrypto",
            dependencies: ["BlueBandCrypto"]
        ),
        .target(
            name: "BlueBandCore",
            dependencies: ["BlueBandProtocol", "BlueBandCrypto"]
        ),
        .testTarget(
            name: "BlueBandProtocolTests",
            dependencies: ["BlueBandProtocol"]
        ),
        .testTarget(
            name: "BlueBandCryptoTests",
            dependencies: [
                "BlueBandCrypto",
                "BlueBandProtocol",
                "CryptoSwift",
            ]
        ),
        .testTarget(
            name: "BlueBandCoreTests",
            dependencies: ["BlueBandCore", "BlueBandProtocol", "BlueBandCrypto", "CryptoSwift"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
