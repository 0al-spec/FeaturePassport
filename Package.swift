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
        .package(url: "https://github.com/ajevans99/swift-json-schema", exact: "0.13.2")
    ],
    targets: [
        .target(
            name: "FeaturePassport",
            dependencies: [
                .product(name: "JSONSchema", package: "swift-json-schema")
            ],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "FeaturePassportCLI",
            dependencies: ["FeaturePassport"]
        ),
        .testTarget(
            name: "FeaturePassportTests",
            dependencies: ["FeaturePassport"]
        )
    ]
)
