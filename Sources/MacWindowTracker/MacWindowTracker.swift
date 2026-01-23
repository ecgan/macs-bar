// MacWindowTracker
// A lightweight Swift library for tracking macOS windows, inspired by AeroSpace's
// battle-tested patterns for handling unreliable macOS Accessibility notifications.
//
// Key features:
// - Real-time window tracking using hybrid AX notifications + polling
// - Automatic Space awareness via CGWindowListCopyWindowInfo
// - Monitor detection and window-to-monitor mapping
// - Focus state tracking
// - SwiftUI-friendly ObservableObject API
//
// Usage:
//   let tracker = WindowTracker()
//   try await tracker.start()
//
//   // Access windows
//   for window in tracker.windows {
//       print("\(window.appName): \(window.title ?? "Untitled")")
//   }
//
//   // Filter by monitor
//   let currentMonitorWindows = tracker.windows(on: tracker.monitors[0])

// Re-export public types
@_exported import struct CoreGraphics.CGWindowID
@_exported import struct CoreGraphics.CGRect
@_exported import struct CoreGraphics.CGPoint
@_exported import struct CoreGraphics.CGSize
