// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacsBar",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../lib"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1"),
    ],
    targets: [
        .executableTarget(
            name: "MacsBar",
            dependencies: [
                .product(name: "MacWindowTracker", package: "lib"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/MacsBar"
        ),
        .testTarget(
            name: "MacsBarTests",
            dependencies: ["MacsBar"],
            path: "Tests/MacsBarTests"
        ),
    ]
)
