// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VibeMD",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "VibeMDCore", targets: ["VibeMDCore"]),
        .executable(name: "VibeMD", targets: ["VibeMDApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.7.0"),
    ],
    targets: [
        .target(
            name: "VibeMDCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .executableTarget(
            name: "VibeMDApp",
            dependencies: ["VibeMDCore"]
        ),
        .testTarget(
            name: "VibeMDCoreTests",
            dependencies: ["VibeMDCore"]
        ),
        .testTarget(
            name: "VibeMDAppTests",
            dependencies: ["VibeMDApp"]
        ),
    ]
)
