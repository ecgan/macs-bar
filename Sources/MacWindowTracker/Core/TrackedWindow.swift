import AppKit
import CoreGraphics

/// Represents a tracked window on screen
public struct TrackedWindow: Identifiable, Hashable, Sendable {
    /// The unique window ID (CGWindowID)
    public let id: CGWindowID

    /// The window title (may be nil for some windows)
    public let title: String?

    /// The name of the owning application
    public let appName: String

    /// The bundle identifier of the owning application (may be nil)
    public let appBundleId: String?

    /// The process ID of the owning application
    public let appPid: pid_t

    /// The window's frame in screen coordinates
    public let frame: CGRect

    /// The ID of the monitor this window is on (1-based)
    public let monitorId: Int

    /// Whether this window is currently focused
    public let isFocused: Bool

    public init(
        id: CGWindowID,
        title: String?,
        appName: String,
        appBundleId: String?,
        appPid: pid_t,
        frame: CGRect,
        monitorId: Int,
        isFocused: Bool
    ) {
        self.id = id
        self.title = title
        self.appName = appName
        self.appBundleId = appBundleId
        self.appPid = appPid
        self.frame = frame
        self.monitorId = monitorId
        self.isFocused = isFocused
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: TrackedWindow, rhs: TrackedWindow) -> Bool {
        lhs.id == rhs.id
            && lhs.isFocused == rhs.isFocused
            && lhs.title == rhs.title
            && lhs.frame == rhs.frame
            && lhs.monitorId == rhs.monitorId
    }
}
