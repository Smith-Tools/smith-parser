// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "smith-parser",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "smith-parser",
            targets: ["smith-parser"]
        )
    ],
    dependencies: [
        .package(path: "../smith-foundation"),
        .package(path: "../smith-diagnostics"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMajor(from: "1.5.0"))
    ],
    targets: [
        .executableTarget(
            name: "smith-parser",
            dependencies: [
                .product(name: "SmithProgress", package: "smith-foundation"),
                .product(name: "SmithOutputFormatter", package: "smith-foundation"),
                .product(name: "SBDiagnostics", package: "smith-diagnostics"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/smith-parser"
        ),
        .testTarget(
            name: "smith-parserTests",
            dependencies: ["smith-parser"],
            path: "Tests/smith-parserTests"
        )
    ]
)
