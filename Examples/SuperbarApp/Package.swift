// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SuperbarApp",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "SuperbarApp",
            dependencies: [
                .product(name: "MacWindowTracker", package: "MacWindowTracker"),
            ],
            path: "Sources"
        ),
    ]
)
