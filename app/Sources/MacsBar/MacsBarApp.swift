import SwiftUI
import MacWindowTracker

@main
struct MacsBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Macs Bar", systemImage: "menubar.rectangle") {
            AppContextMenu()
        }

        Settings {
            SettingsView()
        }
    }
}

/// Shared menu content for menu bar and context menus
struct AppContextMenu: View {
    var body: some View {
        SettingsLink {
            Text("Settings...")
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit Macs Bar") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var panels: [Int: NSPanel] = [:]
    var spaceStates: [Int: SpaceBarState] = [:]
    var windowTracker: WindowTracker?
    private let keyboardShortcutHandler = KeyboardShortcutHandler()
    let shortcutStorage = ShortcutStorage()
    private var activeSpaceId: Int = 0

    private let barHeight: CGFloat = 36

    func applicationDidFinishLaunching(_ notification: Notification) {
        let tracker = WindowTracker()
        self.windowTracker = tracker

        // Create initial panel for the current space (starts empty, fills on first refresh)
        let initialSpace = MacWindowTracker.currentSpaceId()
        activeSpaceId = initialSpace
        if let screen = NSScreen.screens.first {
            _ = ensurePanel(forSpace: initialSpace, initialWindows: [], screen: screen)
        }

        keyboardShortcutHandler.tracker = tracker
        keyboardShortcutHandler.shortcutStorage = shortcutStorage
        keyboardShortcutHandler.start()

        tracker.onRefreshComplete = { [weak self] spaceId, windows in
            guard let self else { return }

            // Update activeSpaceId from live CGS value
            activeSpaceId = MacWindowTracker.currentSpaceId()

            if MacWindowTracker.displaysShareSpace() {
                // Shared space mode: one panel on primary display, showing all windows
                guard let screen = NSScreen.screens.first else { return }
                updatePanelForSpace(spaceId, windows: windows, screen: screen)
            } else {
                // Separate spaces mode: one panel per display's current space
                let displaySpaces = MacWindowTracker.spacesPerDisplay()
                for screen in NSScreen.screens {
                    guard let uuid = MacWindowTracker.displayUUID(for: screen),
                          let currentSpaceId = displaySpaces[uuid]?.first else { continue }
                    let screenWindows = windows.filter { $0.frame.intersects(screen.quartzFrame) }
                    updatePanelForSpace(currentSpaceId, windows: screenWindows, screen: screen)
                }
            }

            keyboardShortcutHandler.currentSpaceState = spaceStates[activeSpaceId]

            // Adjust maximized windows using the active space's data
            let activeWindows = spaceStates[activeSpaceId]?.windows ?? windows
            adjustMaximizedWindows(activeWindows, tracker: tracker)

            cleanupInvalidPanels()
        }

        Task {
            do {
                try await tracker.start()
            } catch WindowTrackerError.accessibilityPermissionDenied {
                print("Please grant Accessibility permission in System Preferences > Privacy & Security > Accessibility")
            } catch {
                print("Failed to start window tracker: \(error)")
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    // MARK: - Panel Management

    /// Create a panel for a space if one doesn't exist. Returns true if a new panel was created.
    /// Does not create panels for fullscreen spaces.
    @discardableResult
    private func ensurePanel(forSpace spaceId: Int, initialWindows: [TrackedWindow], screen: NSScreen) -> Bool {
        // Don't create panels for fullscreen spaces
        if MacWindowTracker.isFullScreenSpace(spaceId) { return false }
        guard panels[spaceId] == nil else { return false }

        let state = SpaceBarState(
            spaceId: spaceId,
            onActivate: { [weak windowTracker] window in
                try? await windowTracker?.activateWindow(window)
            },
            onClose: { [weak windowTracker] window in
                windowTracker?.closeWindow(window)
            }
        )
        state.windows = initialWindows

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configurePanelStyle(panel, screen: screen)

        let contentView = MacsBarContentView(state: state)
        panel.contentView = NSHostingView(rootView: contentView)

        // Deferred reveal: hide → order front → move to space → reveal next run loop turn
        // Check fullscreen again before revealing since space status may have changed
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        MacWindowTracker.moveWindowToSpace(panel, spaceId: spaceId)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Don't reveal if we're now on a fullscreen space
            let currentSpace = MacWindowTracker.currentSpaceId()
            if MacWindowTracker.isFullScreenSpace(currentSpace) || MacWindowTracker.isFullScreenSpace(spaceId) {
                return
            }
            // Don't reveal if fullscreen is detected by other methods
            if self.shouldHidePanelForFullscreen(windows: self.spaceStates[spaceId]?.windows ?? [], screen: screen) {
                return
            }
            panel.alphaValue = 1
        }

        panels[spaceId] = panel
        spaceStates[spaceId] = state
        return true
    }

    private func configurePanelStyle(_ panel: NSPanel, screen: NSScreen) {
        let barFrame = NSRect(
            x: screen.frame.origin.x,
            y: screen.frame.origin.y,
            width: screen.frame.width,
            height: barHeight
        )
        panel.setFrame(barFrame, display: false)
        // Use floating level (3) instead of statusBar (25) so fullscreen windows cover us
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        // Remove .fullScreenAuxiliary so we don't appear on native fullscreen spaces
        panel.collectionBehavior = [.ignoresCycle, .transient]
    }

    /// Update or create panel for a space on the given screen.
    /// Handles fullscreen detection and panel visibility.
    private func updatePanelForSpace(_ spaceId: Int, windows: [TrackedWindow], screen: NSScreen) {
        // Check fullscreen BEFORE updating windows to prevent flicker
        let shouldHideForFullscreen = shouldHidePanelForFullscreen(windows: windows, screen: screen)
        if shouldHideForFullscreen {
            panels[spaceId]?.alphaValue = 0
        }

        // Update or create the panel (skip creation if fullscreen detected)
        let isNewPanel = shouldHideForFullscreen ? false : ensurePanel(forSpace: spaceId, initialWindows: windows, screen: screen)
        if !isNewPanel {
            spaceStates[spaceId]?.windows = windows
        }

        // Update final panel visibility (may show panel if fullscreen ended)
        updatePanelVisibility(for: spaceId, windows: windows, screen: screen)
    }

    // MARK: - Cleanup

    private func cleanupInvalidPanels() {
        let validSpaces = MacWindowTracker.allSpaceIds()

        guard !validSpaces.isEmpty else {
            NSLog("[MacsBar] cleanupInvalidPanels: allSpaceIds() returned empty, skipping cleanup")
            return
        }

        let validSet = Set(validSpaces)
        let invalidKeys = panels.keys.filter { !validSet.contains($0) }

        for spaceId in invalidKeys {
            panels[spaceId]?.orderOut(nil)
            panels.removeValue(forKey: spaceId)
            spaceStates.removeValue(forKey: spaceId)
        }
    }

    private func resetAllPanels() {
        keyboardShortcutHandler.currentSpaceState = nil

        for panel in panels.values {
            panel.orderOut(nil)
        }
        panels.removeAll()
        spaceStates.removeAll()

        Task { await windowTracker?.refresh() }
    }

    // MARK: - Maximized Window Adjustment

    private func adjustMaximizedWindows(_ windows: [TrackedWindow], tracker: WindowTracker) {
        guard let mainMonitor = tracker.monitors.first(where: { $0.isMain }) else { return }

        let menuBarHeight = mainMonitor.visibleFrame.origin.y
        let expectedMaxHeight = mainMonitor.frame.height - menuBarHeight
        let macsBarTop = mainMonitor.frame.maxY - barHeight
        let tolerance: CGFloat = 2

        for window in windows {
            guard window.monitorId == mainMonitor.id else { continue }

            let widthMatches = abs(window.frame.width - mainMonitor.frame.width) <= tolerance
            let heightMatches = abs(window.frame.height - expectedMaxHeight) <= tolerance
            guard widthMatches && heightMatches else { continue }

            guard window.frame.maxY > macsBarTop else { continue }

            let newHeight = expectedMaxHeight - barHeight
            tracker.resizeWindow(window, to: CGSize(width: window.frame.width, height: newHeight))
        }
    }

    // MARK: - Fullscreen Detection

    /// Quick check if we should hide the panel for fullscreen.
    /// Called BEFORE updating windows to prevent flicker during fullscreen transitions.
    private func shouldHidePanelForFullscreen(windows: [TrackedWindow], screen: NSScreen) -> Bool {
        // Method 1: Check if the active space is a native fullscreen space (Chrome, Finder, etc.)
        if MacWindowTracker.isFullScreenSpace(activeSpaceId) {
            return true
        }

        // Method 2: Check frontmost app's window via Accessibility API
        if isFrontmostAppFullscreen(screen: screen) {
            return true
        }

        // Method 3: Check frontmost app's windows for app-controlled fullscreen (e.g., VLC)
        // Only check windows belonging to the frontmost app, not all windows on screen.
        // This prevents false positives from maximized background windows.
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            let frontAppWindows = windows.filter { $0.appPid == frontApp.processIdentifier }
            if frontAppWindows.contains(where: { isAppControlledFullscreen(window: $0, screen: screen) }) {
                return true
            }
        }

        return false
    }

    /// Hide panel when fullscreen is detected.
    /// Uses multiple detection methods since some apps (VLC) don't expose their fullscreen windows.
    private func updatePanelVisibility(for spaceId: Int, windows: [TrackedWindow], screen: NSScreen) {
        guard let panel = panels[spaceId] else { return }

        // Method 1: Check frontmost app's window via Accessibility API
        let axFullscreen = isFrontmostAppFullscreen(screen: screen)

        // Method 2: Check frontmost app's windows for app-controlled fullscreen
        // Only check windows belonging to the frontmost app, not all windows on screen.
        var hasFullscreenWindow = false
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            let frontAppWindows = windows.filter { $0.appPid == frontApp.processIdentifier }
            hasFullscreenWindow = frontAppWindows.contains { isAppControlledFullscreen(window: $0, screen: screen) }
        }

        let shouldHide = axFullscreen || hasFullscreenWindow
        panel.alphaValue = shouldHide ? 0 : 1
    }

    /// Check if frontmost application's focused window is fullscreen using Accessibility API
    private func isFrontmostAppFullscreen(screen: NSScreen) -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        // Get the focused window
        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        guard result == .success, let windowElement = focusedWindow else { return false }

        // Verify this is actually a window, not the desktop or other UI element
        // When clicking the desktop, Finder reports the desktop as "focused window" but it's not a real window
        let axWindow = windowElement as! AXUIElement
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWindow, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String, role != "AXWindow" {
            return false
        }

        // Check if window is fullscreen via AXFullScreen attribute
        var isFullscreen: CFTypeRef?
        let fsResult = AXUIElementCopyAttributeValue(windowElement as! AXUIElement, "AXFullScreen" as CFString, &isFullscreen)
        if fsResult == .success, let fs = isFullscreen as? Bool, fs {
            return true
        }

        // Fallback: Check window size against screen
        var position: CFTypeRef?
        var size: CFTypeRef?
        AXUIElementCopyAttributeValue(windowElement as! AXUIElement, kAXPositionAttribute as CFString, &position)
        AXUIElementCopyAttributeValue(windowElement as! AXUIElement, kAXSizeAttribute as CFString, &size)

        if let pos = position, let sz = size {
            var point = CGPoint.zero
            var winSize = CGSize.zero
            AXValueGetValue(pos as! AXValue, .cgPoint, &point)
            AXValueGetValue(sz as! AXValue, .cgSize, &winSize)

            let tolerance: CGFloat = 5
            return abs(winSize.width - screen.frame.width) <= tolerance
                && abs(winSize.height - screen.frame.height) <= tolerance
                && point.y <= tolerance
        }

        return false
    }

    /// Check if a window is fullscreen (either native macOS fullscreen or app-controlled).
    /// Native fullscreen: window starts at menu bar (y ≈ 30) and extends to bottom
    /// App-controlled fullscreen: window covers entire screen including menu bar (y = 0)
    private func isAppControlledFullscreen(window: TrackedWindow, screen: NSScreen) -> Bool {
        let tolerance: CGFloat = 5
        let screenFrame = screen.frame
        // Note: window.frame uses Quartz coordinates (origin at top-left, y increases downward)
        // screenFrame uses Cocoa coordinates but we only care about width/height here

        let coversFullWidth = abs(window.frame.width - screenFrame.width) <= tolerance

        // Check if window extends to the bottom of the screen
        // In Quartz coords: window bottom = window.origin.y + window.height
        let windowBottom = window.frame.origin.y + window.frame.height
        let extendsToBottom = abs(windowBottom - screenFrame.height) <= tolerance

        // Native fullscreen: starts at menu bar (~30px), covers rest of screen
        // App fullscreen: starts at 0, covers entire screen
        let menuBarHeight: CGFloat = 30
        let isNativeFullscreen = window.frame.origin.y <= menuBarHeight + tolerance
            && window.frame.height >= screenFrame.height - menuBarHeight - tolerance
        let isAppFullscreen = window.frame.origin.y <= tolerance
            && abs(window.frame.height - screenFrame.height) <= tolerance

        let isFullscreen = coversFullWidth && extendsToBottom && (isNativeFullscreen || isAppFullscreen)

        return isFullscreen
    }

    // MARK: - Screen Changes

    @objc private func screenDidChange() {
        activeSpaceId = MacWindowTracker.currentSpaceId()
        resetAllPanels()
    }
}

// MARK: - NSScreen Coordinate Conversion

private extension NSScreen {
    /// Convert screen frame from Cocoa coordinates (origin at bottom-left of primary screen,
    /// Y increases upward) to Quartz coordinates (origin at top-left of primary screen,
    /// Y increases downward). This matches how TrackedWindow.frame is reported.
    var quartzFrame: CGRect {
        guard let mainScreen = NSScreen.screens.first else { return frame }
        let mainHeight = mainScreen.frame.height
        return CGRect(
            x: frame.origin.x,
            y: mainHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
    }
}
