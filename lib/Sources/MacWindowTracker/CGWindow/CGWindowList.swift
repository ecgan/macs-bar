import CoreGraphics
import AppKit

/// Raw window information from CGWindowListCopyWindowInfo
struct CGWindowInfo {
    let windowId: CGWindowID
    let ownerPid: pid_t
    let ownerName: String
    let title: String?
    let bounds: CGRect
    let layer: Int32
    let isOnScreen: Bool
}

/// Wrapper around CGWindowListCopyWindowInfo for querying on-screen windows
enum CGWindowList {
    /// Get all on-screen windows at the normal window level (layer 0).
    /// This automatically respects macOS Spaces - only windows on the current Space are returned.
    static func onScreenWindows() -> [CGWindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return windowList.compactMap { dict -> CGWindowInfo? in
            guard
                let windowId = dict[kCGWindowNumber as String] as? CGWindowID,
                let ownerPid = dict[kCGWindowOwnerPID as String] as? pid_t,
                let ownerName = dict[kCGWindowOwnerName as String] as? String,
                let boundsDict = dict[kCGWindowBounds as String] as? [String: CGFloat],
                let layer = dict[kCGWindowLayer as String] as? Int32
            else {
                return nil
            }

            // Only include normal windows (layer 0)
            // Skip menu bar, dock, overlays, etc.
            guard layer == 0 else { return nil }

            let title = dict[kCGWindowName as String] as? String

            // Parse bounds dictionary
            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )

            // Skip windows with zero size (likely invisible or utility windows)
            guard bounds.width > 0 && bounds.height > 0 else { return nil }

            let isOnScreen = dict[kCGWindowIsOnscreen as String] as? Bool ?? true

            return CGWindowInfo(
                windowId: windowId,
                ownerPid: ownerPid,
                ownerName: ownerName,
                title: title,
                bounds: bounds,
                layer: layer,
                isOnScreen: isOnScreen
            )
        }
    }

    /// Get the bundle identifier for a process by PID
    static func bundleId(forPid pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    /// Get all running applications
    static func runningApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
    }
}
