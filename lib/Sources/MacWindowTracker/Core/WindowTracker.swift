import AppKit
import Combine

/// Main entry point for tracking macOS windows.
/// Provides a SwiftUI-friendly ObservableObject with published state.
///
/// Uses a hybrid approach for reliability:
/// - CGWindowListCopyWindowInfo for window enumeration (respects Spaces)
/// - AX notifications for real-time updates
/// - Periodic polling as a safety net
/// - Mouse click events as fallback (because AX notifications are unreliable)
@MainActor
public final class WindowTracker: ObservableObject {
    // MARK: - State

    /// All on-screen windows
    public private(set) var windows: [TrackedWindow] = []

    /// The currently focused window ID (nil if no window is focused)
    public private(set) var focusedWindowId: CGWindowID?

    /// All connected monitors
    @Published public private(set) var monitors: [TrackedMonitor] = []

    /// The current space ID (updated each refresh)
    public private(set) var currentSpaceId: Int = 0

    /// Callback delivering (spaceId, windows) as an atomic snapshot after each refresh.
    public var onRefreshComplete: ((_ spaceId: Int, _ windows: [TrackedWindow]) -> Void)?

    // MARK: - Internal Components

    private let monitorManager: MonitorManager
    private var appObserverManager: AppObserverManager?
    private var refreshManager: RefreshManager?
    private var monitorCancellable: AnyCancellable?

    // MARK: - Configuration

    /// Whether to include windows with empty titles
    public var includeUntitledWindows: Bool = true

    /// Minimum window size to include (filters out tiny utility windows)
    public var minimumWindowSize: CGSize = CGSize(width: 50, height: 50)

    // MARK: - Initialization

    public init() {
        self.monitorManager = MonitorManager()
    }

    // MARK: - Lifecycle

    /// Start tracking windows.
    /// Requires accessibility permissions to be granted.
    public func start() async throws {
        // Check accessibility permissions
        guard AXIsProcessTrusted() else {
            // Prompt for permissions - use string literal to avoid concurrency warning
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            throw WindowTrackerError.accessibilityPermissionDenied
        }

        // Set up monitor tracking
        monitorCancellable = monitorManager.$monitors
            .receive(on: DispatchQueue.main)
            .sink { [weak self] monitors in
                self?.monitors = monitors
            }
        monitors = monitorManager.monitors

        // Set up AX observers for each app
        appObserverManager = AppObserverManager { [weak self] notification in
            self?.handleAXNotification(notification)
        }
        appObserverManager?.start()

        // Set up refresh manager
        refreshManager = RefreshManager { [weak self] event in
            await self?.performRefresh(event: event)
        }
        refreshManager?.start()

        // Record initial space
        currentSpaceId = MacWindowTracker.currentSpaceId()

        // Initial refresh
        await performRefresh(event: .manual)
    }

    /// Stop tracking windows
    public func stop() {
        refreshManager?.stop()
        refreshManager = nil

        appObserverManager?.stop()
        appObserverManager = nil

        monitorCancellable?.cancel()
        monitorCancellable = nil

        windows = []
        focusedWindowId = nil
        currentSpaceId = 0
    }

    /// Manually trigger a refresh
    public func refresh() async {
        await performRefresh(event: .manual)
    }

    // MARK: - Filtering

    /// Get windows on a specific monitor
    public func windows(on monitor: TrackedMonitor) -> [TrackedWindow] {
        windows.filter { $0.monitorId == monitor.id }
    }

    /// Get windows for a specific application
    public func windows(forApp bundleId: String) -> [TrackedWindow] {
        windows.filter { $0.appBundleId == bundleId }
    }

    /// Get the currently focused window
    public var focusedWindow: TrackedWindow? {
        guard let id = focusedWindowId else { return nil }
        return windows.first { $0.id == id }
    }

    // MARK: - Window Actions

    /// Activate (focus) a window by bringing it to front
    public func activateWindow(_ window: TrackedWindow) async throws {
        // Use AX to raise the specific window (this also activates the owning app)
        let axApp = AXUIElement.application(pid: window.appPid)

        // Get windows and find the matching one
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else {
            return
        }

        for axWindow in axWindows {
            if axWindow.windowId() == window.id {
                axWindow.raise()
                axWindow.setMain(true)
                break
            }
        }

        // Activate the app *after* raising the specific window so macOS
        // gives it keyboard focus without reordering other windows.
        guard let app = NSRunningApplication(processIdentifier: window.appPid) else {
            throw WindowTrackerError.appNotFound
        }
        app.activate()

        // Refresh to update focus state
        refreshManager?.scheduleRefresh(.manual)
    }

    /// Close a window
    public func closeWindow(_ window: TrackedWindow) {
        let axApp = AXUIElement.application(pid: window.appPid)

        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else {
            return
        }

        for axWindow in axWindows {
            if axWindow.windowId() == window.id {
                axWindow.close()
                break
            }
        }

        // Refresh to update window list
        refreshManager?.scheduleRefresh(.manual)
    }

    /// Resize a window to the given size
    public func resizeWindow(_ window: TrackedWindow, to size: CGSize) {
        let axApp = AXUIElement.application(pid: window.appPid)

        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else {
            return
        }

        for axWindow in axWindows {
            if axWindow.windowId() == window.id {
                axWindow.setSize(size)
                break
            }
        }
    }

    // MARK: - Private

    private func handleAXNotification(_ notification: AXNotification) {
        refreshManager?.scheduleRefresh(.axNotification(notification.notificationName))
    }

    private func performRefresh(event: RefreshEvent) async {
        // Update current space ID
        currentSpaceId = MacWindowTracker.currentSpaceId()

        // Get all on-screen windows from CGWindowList
        let cgWindows = CGWindowList.onScreenWindows()

        // Get focused window via AX
        let focusedInfo = try? await appObserverManager?.getFocusedWindow()
        let newFocusedId = focusedInfo?.windowId

        // Build AX title lookup for windows missing CGWindowName
        // (kCGWindowName requires Screen Recording permission; AX titles work with just Accessibility)
        let axTitles = Self.axTitleLookup(for: cgWindows)

        // Build AX subrole lookup to filter out popup/dropdown windows
        // (e.g. Chrome's omnibox dropdown creates a separate window that isn't a standard window)
        let standardWindowIds = Self.axStandardWindowIds(for: cgWindows)

        // Build tracked windows list
        var newWindows: [TrackedWindow] = []
        var appCache: [pid_t: NSRunningApplication] = [:]

        for cgWindow in cgWindows {
            // Skip non-standard windows (popups, dropdowns, dialogs, etc.)
            if !standardWindowIds.contains(cgWindow.windowId) {
                continue
            }
            // Apply size filter
            guard cgWindow.bounds.width >= minimumWindowSize.width,
                  cgWindow.bounds.height >= minimumWindowSize.height else {
                continue
            }

            // Apply title filter
            if !includeUntitledWindows && (cgWindow.title?.isEmpty ?? true) {
                continue
            }

            // Skip windows from non-regular apps.
            // Only regular apps (those that appear in the Dock) have user-manageable windows.
            // This filters out background utilities (e.g. "borders"), overlay apps, and
            // unbundled processes that aren't proper macOS apps.
            let app: NSRunningApplication? = appCache[cgWindow.ownerPid] ?? {
                let resolved = NSRunningApplication(processIdentifier: cgWindow.ownerPid)
                if let resolved { appCache[cgWindow.ownerPid] = resolved }
                return resolved
            }()
            guard let app, app.activationPolicy == .regular else {
                continue
            }

            let bundleId = app.bundleIdentifier
            let monitorId = monitorManager.monitorId(forWindowFrame: cgWindow.bounds)

            let trackedWindow = TrackedWindow(
                id: cgWindow.windowId,
                title: cgWindow.title ?? axTitles[cgWindow.windowId],
                appName: cgWindow.ownerName,
                appBundleId: bundleId,
                appPid: cgWindow.ownerPid,
                frame: cgWindow.bounds,
                monitorId: monitorId,
                isFocused: cgWindow.windowId == newFocusedId
            )

            newWindows.append(trackedWindow)
        }

        // Sort by window ID (lower IDs were created earlier)
        newWindows.sort { $0.id < $1.id }

        // Update state and fire callback
        self.windows = newWindows
        self.focusedWindowId = newFocusedId
        onRefreshComplete?(currentSpaceId, newWindows)
    }

    /// Build a set of window IDs that are standard windows (AXStandardWindow subrole).
    /// Popup/dropdown windows (e.g. Chrome's omnibox dropdown) have different subroles
    /// and should not appear in a taskbar-style UI.
    private static func axStandardWindowIds(for cgWindows: [CGWindowInfo]) -> Set<CGWindowID> {
        let pids = Set(cgWindows.map { $0.ownerPid })
        var result: Set<CGWindowID> = []

        for pid in pids {
            let axApp = AXUIElement.application(pid: pid)
            var windowsRef: AnyObject?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let axWindows = windowsRef as? [AXUIElement] else {
                continue
            }

            for axWindow in axWindows {
                guard let windowId = axWindow.windowId() else { continue }
                let subrole = axWindow.subrole
                if subrole == "AXStandardWindow" {
                    result.insert(windowId)
                }
            }
        }

        return result
    }

    /// Build a windowId → title lookup using the Accessibility API.
    /// Used as a fallback when CGWindowList doesn't provide titles (no Screen Recording permission).
    private static func axTitleLookup(for cgWindows: [CGWindowInfo]) -> [CGWindowID: String] {
        // Collect PIDs that have at least one window with a nil title
        let pidsNeedingTitles = Set(cgWindows.filter { $0.title == nil }.map { $0.ownerPid })
        guard !pidsNeedingTitles.isEmpty else { return [:] }

        var lookup: [CGWindowID: String] = [:]

        for pid in pidsNeedingTitles {
            let axApp = AXUIElement.application(pid: pid)
            var windowsRef: AnyObject?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let axWindows = windowsRef as? [AXUIElement] else {
                continue
            }

            for axWindow in axWindows {
                guard let windowId = axWindow.windowId(),
                      let title = axWindow.title, !title.isEmpty else {
                    continue
                }
                lookup[windowId] = title
            }
        }

        return lookup
    }
}

// MARK: - Errors

public enum WindowTrackerError: Error, LocalizedError {
    case accessibilityPermissionDenied
    case appNotFound

    public var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied:
            return "Accessibility permission is required to track windows. Please grant permission in System Preferences > Privacy & Security > Accessibility."
        case .appNotFound:
            return "The application for this window could not be found."
        }
    }
}
