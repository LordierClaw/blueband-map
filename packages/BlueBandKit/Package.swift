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
    ],
    targets: [
        .target(name: "BlueBandProtocol"),
        .testTarget(
            name: "BlueBandProtocolTests",
            dependencies: ["BlueBandProtocol"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
