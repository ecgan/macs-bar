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

            // Filter to primary display only
            let primaryScreenFrame = NSScreen.screens.first?.frame ?? .zero
            let filteredWindows = windows.filter { window in
                window.frame.intersects(primaryScreenFrame)
            }

            // Update activeSpaceId from live CGS value
            activeSpaceId = MacWindowTracker.currentSpaceId()

            // Update the snapshot space's panel
            let isNewPanel = ensurePanel(forSpace: spaceId, initialWindows: filteredWindows)
            if !isNewPanel {
                spaceStates[spaceId]?.windows = filteredWindows
            }

            // Ensure the active space has a panel (rapid switching: A→B→C)
            if spaceStates[activeSpaceId] == nil {
                _ = ensurePanel(forSpace: activeSpaceId, initialWindows: [])
            }

            keyboardShortcutHandler.currentSpaceState = spaceStates[activeSpaceId]

            // Adjust maximized windows using the active space's data
            let activeWindows = spaceStates[activeSpaceId]?.windows ?? filteredWindows
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
    @discardableResult
    private func ensurePanel(forSpace spaceId: Int, initialWindows: [TrackedWindow]) -> Bool {
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
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        MacWindowTracker.moveWindowToSpace(panel, spaceId: spaceId)
        DispatchQueue.main.async {
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
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary, .transient]
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

    // MARK: - Screen Changes

    @objc private func screenDidChange() {
        activeSpaceId = MacWindowTracker.currentSpaceId()
        resetAllPanels()
    }
}
