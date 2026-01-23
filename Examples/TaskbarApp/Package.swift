// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TaskbarApp",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "TaskbarApp",
            dependencies: [
                .product(name: "MacWindowTracker", package: "MacWindowTracker"),
            ],
            path: "Sources"
        ),
    ]
)
