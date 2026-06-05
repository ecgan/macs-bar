import SwiftUI
import MacWindowTracker

@main
struct MacsBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            AppContextMenu()
                .environmentObject(appDelegate.updaterService)
        } label: {
            Image(nsImage: MenuBarIconImage.taskbarTemplate)
                .accessibilityLabel("Macs Bar")
        }

        Settings {
            SettingsView()
                .environmentObject(appDelegate.shortcutStorage)
                .environmentObject(appDelegate.updaterService)
        }
    }
}

/// Shared menu content for menu bar and context menus
struct AppContextMenu: View {
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var updaterService: UpdaterService

    var body: some View {
        Button("Check for Updates...") {
            updaterService.checkForUpdates()
        }
        .disabled(!updaterService.canCheckForUpdates)

        // Note: We intentionally stay as .accessory and don't switch to .regular when
        // opening Settings. This is the common pattern for menu bar utility apps (e.g.,
        // Rectangle, Magnet). The tradeoff is no Cmd+Tab or Window menu, but it avoids
        // complexity with activation policy switching and edge cases with window tracking.
        Button("Settings...") {
            openSettings()
            // Bring settings window to front if already open (openSettings() alone won't do this)
            DispatchQueue.main.async {
                if let window = NSApp.settingsWindow {
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate()
                }
            }
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
    let updaterService = UpdaterService()
    private var activeSpaceId: Int = 0

    private let barHeight: CGFloat = 36

    func applicationDidFinishLaunching(_ notification: Notification) {
        // IMPORTANT: This must be called at runtime even though LSUIElement=true in Info.plist.
        // Without this, keyboard shortcuts become slow (~200ms delay) because NSApp.activate()
        // in KeyboardShortcutHandler takes longer for non-accessory apps. Do not remove.
        NSApp.setActivationPolicy(.accessory)

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

        // Hide Settings window during activation to prevent flash when NSApp.activate() is called
        // (but only if we're not activating the Settings window itself)
        //
        // Known issues:
        // - UI hang may occur when Rectangle app's settings window is open. Closing Rectangle's
        //   settings window resolves this. This appears to be due to Rectangle (an accessory app)
        //   becoming unresponsive to AX calls when its settings window is visible.
        // - Our Settings window gets sent to the back when activating other windows. This is a
        //   tradeoff to fix the z-order issue where Settings would incorrectly become the second
        //   frontmost window. Users can bring Settings back to front by clicking on it.
        tracker.willActivateWindow = { (target: TrackedWindow) in
            // Skip if target is our own app (e.g., Settings window)
            let isOwnApp = target.appBundleId == Bundle.main.bundleIdentifier
            if isOwnApp { return }

            if let settingsWindow = NSApp.settingsWindow, settingsWindow.isVisible {
                settingsWindow.alphaValue = 0
            }
        }

        // Restore Settings window after activation, but order it to back to fix z-order
        tracker.didActivateWindow = { (target: TrackedWindow) in
            // Skip if target is our own app (e.g., Settings window)
            let isOwnApp = target.appBundleId == Bundle.main.bundleIdentifier
            if isOwnApp { return }

            if let settingsWindow = NSApp.settingsWindow, settingsWindow.alphaValue == 0 {
                settingsWindow.orderBack(nil)
                settingsWindow.alphaValue = 1
            }
        }

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

            // Keep cascaded windows opened from a maximized source inside the Macs Bar safe frame
            let activeWindows = spaceStates[activeSpaceId]?.windows ?? windows
            adjustCascadedWindowsFromMaximizedSource(activeWindows, tracker: tracker)

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
            .environmentObject(updaterService)
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
            if self.shouldHidePanelForFullscreen(spaceId: spaceId, windows: self.spaceStates[spaceId]?.windows ?? [], screen: screen) {
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
        let shouldHideForFullscreen = shouldHidePanelForFullscreen(spaceId: spaceId, windows: windows, screen: screen)
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

    // MARK: - Cascaded Window Adjustment

    private func adjustCascadedWindowsFromMaximizedSource(_ windows: [TrackedWindow], tracker: WindowTracker) {
        let monitorsById = Dictionary(uniqueKeysWithValues: tracker.monitors.map { ($0.id, $0) })

        for window in windows {
            guard let monitor = monitorsById[window.monitorId] else { continue }
            guard let adjustedFrame = MaximizedWindowCascadeAdjuster.adjustedFrame(
                for: window.frame,
                monitorFrame: monitor.frame,
                visibleFrame: monitor.visibleFrame,
                barHeight: barHeight
            ) else {
                continue
            }

            tracker.setWindowFrame(window, to: adjustedFrame)
        }
    }

    // MARK: - Fullscreen Detection

    /// Quick check if we should hide the panel for fullscreen.
    /// Called BEFORE updating windows to prevent flicker during fullscreen transitions.
    private func shouldHidePanelForFullscreen(spaceId: Int, windows: [TrackedWindow], screen: NSScreen) -> Bool {
        // Method 1: Check if the space is a native fullscreen space
        if MacWindowTracker.isFullScreenSpace(spaceId) {
            return true
        }

        // Method 2: Check if the focused window is fullscreen (using the async-loaded value from tracker)
        if let tracker = windowTracker, tracker.isFocusedWindowFullscreen {
            return true
        }

        // Method 3: Check if any window belonging to the frontmost app is fullscreen on this screen
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            let frontAppWindows = windows.filter { $0.appPid == frontApp.processIdentifier }
            if frontAppWindows.contains(where: { isAppControlledFullscreen(window: $0, screen: screen) }) {
                return true
            }
        }

        return false
    }

    /// Hide panel when fullscreen is detected.
    private func updatePanelVisibility(for spaceId: Int, windows: [TrackedWindow], screen: NSScreen) {
        guard let panel = panels[spaceId] else { return }

        let shouldHide = shouldHidePanelForFullscreen(spaceId: spaceId, windows: windows, screen: screen)
        panel.alphaValue = shouldHide ? 0 : 1
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

// MARK: - Settings Window Lookup

private extension NSApplication {
    /// Undocumented SwiftUI identifier for the Settings window. May change across macOS versions.
    static let settingsWindowId = "com_apple_SwiftUI_Settings_window"

    /// Find the SwiftUI Settings window, if it exists.
    var settingsWindow: NSWindow? {
        windows.first { $0.identifier?.rawValue == Self.settingsWindowId }
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
