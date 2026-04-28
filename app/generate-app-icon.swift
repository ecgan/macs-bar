import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

let fileManager = FileManager.default
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let appDir = scriptURL.deletingLastPathComponent()
let sourceDir = appDir.appendingPathComponent("Resources", isDirectory: true)
let assetIconsetDir = appDir.appendingPathComponent("Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let outputURL = appDir.appendingPathComponent("Resources/AppIcon.icns")

let iconMappings = [
    ("AppIcon16.png", "icon_16x16.png"),
    ("AppIcon32.png", "icon_16x16@2x.png"),
    ("AppIcon32.png", "icon_32x32.png"),
    ("AppIcon64.png", "icon_32x32@2x.png"),
    ("AppIcon128.png", "icon_128x128.png"),
    ("AppIcon256.png", "icon_128x128@2x.png"),
    ("AppIcon256.png", "icon_256x256.png"),
    ("AppIcon512.png", "icon_256x256@2x.png"),
    ("AppIcon512.png", "icon_512x512.png"),
    ("AppIcon1024.png", "icon_512x512@2x.png"),
]

try fileManager.createDirectory(at: assetIconsetDir, withIntermediateDirectories: true)

for (sourceName, destinationName) in iconMappings {
    let sourceURL = sourceDir.appendingPathComponent(sourceName)

    guard fileManager.fileExists(atPath: sourceURL.path) else {
        fputs("Missing source icon file: \(sourceURL.path)\n", stderr)
        exit(1)
    }

    let destinationURL = assetIconsetDir.appendingPathComponent(destinationName)
    if fileManager.fileExists(atPath: destinationURL.path) {
        try fileManager.removeItem(at: destinationURL)
    }
    try fileManager.copyItem(at: sourceURL, to: destinationURL)
}

guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    UTType.icns.identifier as CFString,
    iconMappings.count,
    nil
) else {
    fputs("Failed to create icns destination at \(outputURL.path)\n", stderr)
    exit(1)
}

for (_, iconName) in iconMappings {
    let iconURL = assetIconsetDir.appendingPathComponent(iconName)
    guard let source = CGImageSourceCreateWithURL(iconURL as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fputs("Failed to load PNG: \(iconURL.path)\n", stderr)
        exit(1)
    }

    CGImageDestinationAddImage(destination, image, nil)
}

guard CGImageDestinationFinalize(destination) else {
    fputs("Failed to finalize icns file at \(outputURL.path)\n", stderr)
    exit(1)
}

print("Generated \(outputURL.path)")
