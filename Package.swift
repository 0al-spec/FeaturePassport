// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FeaturePassport",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(name: "FeaturePassport", targets: ["FeaturePassport"]),
        .executable(name: "feature-passport", targets: ["FeaturePassportCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/ajevans99/swift-json-schema", exact: "0.13.2"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "604.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.5.1")
    ],
    targets: [
        .target(
            name: "FeaturePassport",
            dependencies: [
                .product(name: "JSONSchema", package: "swift-json-schema"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "Crypto", package: "swift-crypto")
            ],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "FeaturePassportCLI",
            dependencies: ["FeaturePassport", .product(name: "Crypto", package: "swift-crypto")]
        ),
        .testTarget(
            name: "FeaturePassportTests",
            dependencies: ["FeaturePassport"]
        )
    ]
)
