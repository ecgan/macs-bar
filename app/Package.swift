// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacsBar",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../lib"),
    ],
    targets: [
        .executableTarget(
            name: "MacsBar",
            dependencies: [
                .product(name: "MacWindowTracker", package: "lib"),
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
