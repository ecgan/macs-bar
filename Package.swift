// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacWindowTracker",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "MacWindowTracker",
            targets: ["MacWindowTracker"]
        ),
    ],
    targets: [
        .target(
            name: "MacWindowTracker",
            dependencies: [],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "MacWindowTrackerTests",
            dependencies: ["MacWindowTracker"]
        ),
    ]
)
