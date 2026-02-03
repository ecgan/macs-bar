import SwiftUI
import MacWindowTracker

@main
struct SuperbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var panels: [Int: NSPanel] = [:]
    var spaceStates: [Int: SpaceBarState] = [:]
    var windowTracker: WindowTracker?
    private let keyboardShortcutHandler = KeyboardShortcutHandler()
    private var activeSpaceId: Int = 0

    private let barHeight: CGFloat = 36

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let tracker = WindowTracker()
        self.windowTracker = tracker

        // Create initial panel for the current space (starts empty, fills on first refresh)
        let initialSpace = MacWindowTracker.currentSpaceId()
        activeSpaceId = initialSpace
        _ = ensurePanel(forSpace: initialSpace, initialWindows: [])

        keyboardShortcutHandler.tracker = tracker
        keyboardShortcutHandler.start()

        tracker.onRefreshComplete = { [weak self] spaceId, windows in
            guard let self else { return }

            // When "Displays have separate Spaces" is OFF, all displays share one space,
            // so show windows from all displays. Otherwise, filter to primary display only.
            let filteredWindows: [TrackedWindow]
            if MacWindowTracker.displaysShareSpace() {
                filteredWindows = windows
            } else {
                let primaryScreenFrame = NSScreen.screens.first?.frame ?? .zero
                filteredWindows = windows.filter { window in
                    window.frame.intersects(primaryScreenFrame)
                }
            }

            // Update activeSpaceId from live CGS value
            activeSpaceId = MacWindowTracker.currentSpaceId()

            // Check fullscreen BEFORE updating windows to prevent flicker.
            // If we're about to hide the panel, do it before SwiftUI renders the new window list.
            let shouldHideForFullscreen = shouldHidePanelForFullscreen(windows: filteredWindows)
            if shouldHideForFullscreen {
                panels[activeSpaceId]?.alphaValue = 0
            }

            // Update the snapshot space's panel (skip creation if fullscreen detected)
            let isNewPanel = shouldHideForFullscreen ? false : ensurePanel(forSpace: spaceId, initialWindows: filteredWindows)
            if !isNewPanel {
                spaceStates[spaceId]?.windows = filteredWindows
            }

            // Ensure the active space has a panel (rapid switching: A→B→C)
            // But skip if fullscreen is detected - don't create panels for fullscreen spaces
            if spaceStates[activeSpaceId] == nil && !shouldHideForFullscreen {
                _ = ensurePanel(forSpace: activeSpaceId, initialWindows: [])
            }

            keyboardShortcutHandler.currentSpaceState = spaceStates[activeSpaceId]

            // Adjust maximized windows using the active space's data
            let activeWindows = spaceStates[activeSpaceId]?.windows ?? filteredWindows
            adjustMaximizedWindows(activeWindows, tracker: tracker)

            // Update final panel visibility (may show panel if fullscreen ended)
            updatePanelVisibility(for: activeSpaceId, windows: filteredWindows)

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
    private func ensurePanel(forSpace spaceId: Int, initialWindows: [TrackedWindow]) -> Bool {
        // Don't create panels for fullscreen spaces
        if MacWindowTracker.isFullScreenSpace(spaceId) { return false }
        guard panels[spaceId] == nil else { return false }

        let state = SpaceBarState(spaceId: spaceId) { [weak windowTracker] window in
            try? await windowTracker?.activateWindow(window)
        }
        state.windows = initialWindows

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configurePanelStyle(panel)

        let contentView = SuperbarContentView(state: state)
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
            if self.shouldHidePanelForFullscreen(windows: self.spaceStates[spaceId]?.windows ?? []) {
                return
            }
            panel.alphaValue = 1
        }

        panels[spaceId] = panel
        spaceStates[spaceId] = state
        return true
    }

    private func configurePanelStyle(_ panel: NSPanel) {
        let screen = NSScreen.screens.first ?? NSScreen.main!
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

    // MARK: - Cleanup

    private func cleanupInvalidPanels() {
        let validSpaces = MacWindowTracker.allSpaceIds()

        guard !validSpaces.isEmpty else {
            NSLog("[Superbar] cleanupInvalidPanels: allSpaceIds() returned empty, skipping cleanup")
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
        let superbarTop = mainMonitor.frame.maxY - barHeight
        let tolerance: CGFloat = 2

        for window in windows {
            guard window.monitorId == mainMonitor.id else { continue }

            let widthMatches = abs(window.frame.width - mainMonitor.frame.width) <= tolerance
            let heightMatches = abs(window.frame.height - expectedMaxHeight) <= tolerance
            guard widthMatches && heightMatches else { continue }

            guard window.frame.maxY > superbarTop else { continue }

            let newHeight = expectedMaxHeight - barHeight
            tracker.resizeWindow(window, to: CGSize(width: window.frame.width, height: newHeight))
        }
    }

    // MARK: - Fullscreen Detection

    /// Quick check if we should hide the panel for fullscreen.
    /// Called BEFORE updating windows to prevent flicker during fullscreen transitions.
    private func shouldHidePanelForFullscreen(windows: [TrackedWindow]) -> Bool {
        guard let screen = NSScreen.screens.first else { return false }

        // Method 1: Check if the active space is a native fullscreen space (Chrome, Finder, etc.)
        if MacWindowTracker.isFullScreenSpace(activeSpaceId) {
            return true
        }

        // Method 2: Check frontmost app's window via Accessibility API
        if isFrontmostAppFullscreen(screen: screen) {
            return true
        }

        // Method 3: Check tracked windows for app-controlled fullscreen
        if windows.contains(where: { isAppControlledFullscreen(window: $0, screen: screen) }) {
            return true
        }

        return false
    }

    /// Hide panel when fullscreen is detected.
    /// Uses multiple detection methods since some apps (VLC) don't expose their fullscreen windows.
    private func updatePanelVisibility(for spaceId: Int, windows: [TrackedWindow]) {
        guard let panel = panels[spaceId],
              let screen = NSScreen.screens.first else { return }

        // Method 1: Check frontmost app's window via Accessibility API
        let axFullscreen = isFrontmostAppFullscreen(screen: screen)

        // Method 2: Check tracked windows for fullscreen
        let hasFullscreenWindow = windows.contains { isAppControlledFullscreen(window: $0, screen: screen) }

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
