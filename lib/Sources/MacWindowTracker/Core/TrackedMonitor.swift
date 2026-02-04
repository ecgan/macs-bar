import AppKit
import CoreGraphics

/// Represents a tracked monitor/display
public struct TrackedMonitor: Identifiable, Hashable, Sendable {
    /// The monitor ID (1-based index in NSScreen.screens)
    public let id: Int

    /// The localized name of the monitor
    public let name: String

    /// The full frame of the monitor in screen coordinates
    public let frame: CGRect

    /// The visible frame (excluding menu bar and dock)
    public let visibleFrame: CGRect

    /// Whether this is the main monitor (contains the menu bar)
    public let isMain: Bool

    public init(
        id: Int,
        name: String,
        frame: CGRect,
        visibleFrame: CGRect,
        isMain: Bool
    ) {
        self.id = id
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isMain = isMain
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: TrackedMonitor, rhs: TrackedMonitor) -> Bool {
        lhs.id == rhs.id
    }
}
