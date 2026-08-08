import SwiftUI
import Combine
import MacWindowTracker

@main
struct MacsBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            AppContextMenu()
                .environmentObject(appDelegate.updaterService)
                .environmentObject(appDelegate.permissionManager)
                .environmentObject(appDelegate.welcomeGuideController)
        } label: {
            Image(nsImage: MenuBarIconImage.taskbarTemplate)
                .accessibilityLabel("Macs Bar")
        }

        Settings {
            SettingsView()
                .environmentObject(appDelegate.shortcutStorage)
                .environmentObject(appDelegate.updaterService)
                .environmentObject(appDelegate.welcomeGuideController)
        }
    }
}

/// Shared menu content for menu bar and context menus
struct AppContextMenu: View {
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var updaterService: UpdaterService
    @EnvironmentObject private var permissionManager: AccessibilityPermissionManager
    @EnvironmentObject private var welcomeGuideController: WelcomeGuideController

    var body: some View {
        Group {
            if !permissionManager.isPermissionGranted {
                Button("Grant Accessibility Permission...") {
                    permissionManager.openSystemSettings()
                }
                Divider()
            }

            Button("Check for Updates...") {
                updaterService.checkForUpdates()
            }
            .disabled(!updaterService.canCheckForUpdates)

            Button("Welcome Guide...") {
                welcomeGuideController.show()
            }

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
        .onAppear {
            permissionManager.checkStatus()
        }
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
    let permissionManager = AccessibilityPermissionManager()
    lazy var welcomeGuideController = WelcomeGuideController(
        permissionManager: permissionManager,
        shortcutStorage: shortcutStorage
    )
    private var permissionCancellable: AnyCancellable?
    private var settingsCancellable: AnyCancellable?
    private var isTrackerStarted = false
    private var activeSpaceId: Int = 0

    private let barHeight: CGFloat = 36
    private var autoHideEnabled = UserDefaults.standard.bool(forKey: AppSettings.autoHideEnabledKey)
    private var autoHideActivationHeight: CGFloat = {
        let storedValue = UserDefaults.standard.object(
            forKey: AppSettings.autoHideActivationHeightKey
        ) as? Double ?? AppSettings.defaultAutoHideActivationHeight
        let clampedValue = min(
            max(storedValue, AppSettings.autoHideActivationHeightRange.lowerBound),
            AppSettings.autoHideActivationHeightRange.upperBound
        )
        return CGFloat(clampedValue)
    }()
    private var panelLevel = AppSettings.panelLevel()
    private var barPlacementArea = AppSettings.barPlacementArea()
    private var autoHideTimer: Timer?
    private var panelScreenGeometries: [Int: PanelScreenGeometry] = [:]
    private var autoHideShownStates: [Int: Bool] = [:]
    private var pendingAutoHideTransitions: [Int: DispatchWorkItem] = [:]
    private var pendingAutoHideTargets: [Int: Bool] = [:]
    private var fullscreenHiddenSpaces: Set<Int> = []
    private var contextMenuTrackingSpaces: Set<Int> = []
    private var navigationModifiersHeld = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // IMPORTANT: This must be called at runtime even though LSUIElement=true in Info.plist.
        // Without this, keyboard shortcuts become slow (~200ms delay) because NSApp.activate()
        // in KeyboardShortcutHandler takes longer for non-accessory apps. Do not remove.
        NSApp.setActivationPolicy(.accessory)

        let tracker = WindowTracker()
        self.windowTracker = tracker
        keyboardShortcutHandler.onToggleAutoHide = { [weak self] in
            self?.toggleAutoHide()
        }
        keyboardShortcutHandler.onNavigationModifiersChanged = { [weak self] areHeld in
            self?.navigationModifiersDidChange(areHeld)
        }

        // Hide auxiliary windows during activation to prevent a flash when NSApp.activate()
        // is called (but only if we're not activating one of our own windows).
        //
        // Known issues:
        // - UI hang may occur when Rectangle app's settings window is open. Closing Rectangle's
        //   settings window resolves this. This appears to be due to Rectangle (an accessory app)
        //   becoming unresponsive to AX calls when its settings window is visible.
        // - Our Settings window gets sent to the back when activating other windows. This is a
        //   tradeoff to fix the z-order issue where Settings would incorrectly become the second
        //   frontmost window. Users can bring Settings back to front by clicking on it.
        tracker.willActivateWindow = { [weak self] (target: TrackedWindow) in
            guard let self else { return }
            // Skip if target is our own app (e.g., Settings window)
            let isOwnApp = target.appBundleId == Bundle.main.bundleIdentifier
            if isOwnApp { return }

            for window in self.auxiliaryWindows where window.isVisible {
                window.alphaValue = 0
            }
        }

        // Restore auxiliary windows after activation, but order them to back to fix z-order.
        tracker.didActivateWindow = { [weak self] (target: TrackedWindow) in
            guard let self else { return }
            // Skip if target is our own app (e.g., Settings window)
            let isOwnApp = target.appBundleId == Bundle.main.bundleIdentifier
            if isOwnApp { return }

            for window in self.auxiliaryWindows where window.alphaValue == 0 {
                window.orderBack(nil)
                window.alphaValue = 1
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
            // Disabled in Floating Pill UI (Phase 1)
            // let activeWindows = spaceStates[activeSpaceId]?.windows ?? windows
            // adjustCascadedWindowsFromMaximizedSource(activeWindows, tracker: tracker)

            cleanupInvalidPanels()
        }

        // Observe permission changes
        permissionCancellable = permissionManager.$isPermissionGranted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isGranted in
                guard let self else { return }
                if isGranted {
                    Task { @MainActor in
                        await self.setupAndStartTracker()
                    }
                } else {
                    self.tearDownTracker()
                }
            }

        settingsCancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification, object: UserDefaults.standard)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshSettings()
            }

        if welcomeGuideController.shouldPresentAutomatically() {
            DispatchQueue.main.async { [weak self] in
                self?.welcomeGuideController.show(isFirstRun: true)
            }
        } else if !permissionManager.isPermissionGranted {
            permissionManager.promptUserForPermission()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @MainActor
    private func setupAndStartTracker() async {
        guard !isTrackerStarted else { return }
        guard let tracker = self.windowTracker else { return }

        do {
            try await tracker.start()
            isTrackerStarted = true

            // Create initial panel for the current space (starts empty, fills on first refresh)
            let initialSpace = MacWindowTracker.currentSpaceId()
            activeSpaceId = initialSpace
            if let screen = NSScreen.screens.first {
                _ = ensurePanel(forSpace: initialSpace, initialWindows: [], screen: screen)
            }

            keyboardShortcutHandler.tracker = tracker
            keyboardShortcutHandler.shortcutStorage = shortcutStorage
            keyboardShortcutHandler.start()

            if autoHideEnabled {
                startAutoHideTracking()
            }
        } catch {
            print("Failed to start window tracker: \(error)")
        }
    }

    @MainActor
    private func tearDownTracker() {
        guard isTrackerStarted else { return }

        windowTracker?.stop()
        keyboardShortcutHandler.stop()
        stopAutoHideTracking()

        for panel in panels.values {
            panel.orderOut(nil)
        }
        panels.removeAll()
        spaceStates.removeAll()
        panelScreenGeometries.removeAll()
        autoHideShownStates.removeAll()
        fullscreenHiddenSpaces.removeAll()
        contextMenuTrackingSpaces.removeAll()

        isTrackerStarted = false
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

        let panel = MacsBarPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.onContextMenuTrackingChanged = { [weak self] isTracking in
            self?.contextMenuTrackingDidChange(isTracking, for: spaceId)
        }
        configurePanelStyle(panel, screen: screen)

        let contentView = MacsBarContentView(state: state)
            .environmentObject(updaterService)
            .environmentObject(permissionManager)
            .environmentObject(welcomeGuideController)
        let hostingView = MacsBarHostingView(rootView: AnyView(contentView))
        hostingView.state = state
        let panelContentView = MacsBarPanelContentView(
            hostingView: hostingView,
            frame: NSRect(origin: .zero, size: panel.frame.size)
        )
        panelContentView.autoresizingMask = [.width, .height]
        panel.contentView = panelContentView

        panelScreenGeometries[spaceId] = PanelScreenGeometry(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame
        )
        autoHideShownStates[spaceId] = !autoHideEnabled
        panelContentView.setBarShown(!autoHideEnabled, animated: false)

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
        let geometry = PanelScreenGeometry(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame
        )
        let barFrame = PanelPlacementPolicy.barFrame(
            for: geometry,
            area: barPlacementArea,
            barHeight: barHeight
        )
        panel.setFrame(barFrame, display: false)
        panel.level = PanelLevelPolicy.windowLevel(for: panelLevel)
        panel.isOpaque = false
        panel.backgroundColor = .clear
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
            cancelPendingAutoHideTransition(for: spaceId)
            panels[spaceId]?.orderOut(nil)
            panels.removeValue(forKey: spaceId)
            spaceStates.removeValue(forKey: spaceId)
            panelScreenGeometries.removeValue(forKey: spaceId)
            autoHideShownStates.removeValue(forKey: spaceId)
            fullscreenHiddenSpaces.remove(spaceId)
            contextMenuTrackingSpaces.remove(spaceId)
        }
    }

    private func resetAllPanels() {
        keyboardShortcutHandler.currentSpaceState = nil

        for panel in panels.values {
            panel.orderOut(nil)
        }
        cancelAllPendingAutoHideTransitions()
        panels.removeAll()
        spaceStates.removeAll()
        panelScreenGeometries.removeAll()
        autoHideShownStates.removeAll()
        fullscreenHiddenSpaces.removeAll()
        contextMenuTrackingSpaces.removeAll()

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
        if shouldHide {
            fullscreenHiddenSpaces.insert(spaceId)
            cancelPendingAutoHideTransition(for: spaceId)
            if autoHideEnabled {
                setAutoHideShown(false, for: spaceId, animated: false)
            }
            panel.alphaValue = 0
        } else {
            fullscreenHiddenSpaces.remove(spaceId)
            panel.alphaValue = 1
            if !autoHideEnabled {
                setAutoHideShown(true, for: spaceId, animated: false)
            }
        }
    }

    /// Check if a window is fullscreen (app-controlled fullscreen covering the entire screen including menu bar).
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

        // App fullscreen: starts at 0, covers entire screen
        let isAppFullscreen = window.frame.origin.y <= tolerance
            && abs(window.frame.height - screenFrame.height) <= tolerance

        let isFullscreen = coversFullWidth && extendsToBottom && isAppFullscreen

        return isFullscreen
    }

    // MARK: - Screen Changes

    @objc private func screenDidChange() {
        activeSpaceId = MacWindowTracker.currentSpaceId()
        resetAllPanels()
    }

    // MARK: - Settings

    private func refreshSettings() {
        refreshAutoHideSettings()
        refreshPanelLevelSetting()
        refreshPanelPlacementSetting()
    }

    private func refreshPanelLevelSetting() {
        let newValue = AppSettings.panelLevel()
        guard newValue != panelLevel else { return }

        panelLevel = newValue
        let level = PanelLevelPolicy.windowLevel(for: newValue)
        for panel in panels.values {
            panel.level = level
        }
    }

    private func refreshPanelPlacementSetting() {
        let newValue = AppSettings.barPlacementArea()
        guard newValue != barPlacementArea else { return }

        barPlacementArea = newValue
        for (spaceId, panel) in panels {
            guard let geometry = panelScreenGeometries[spaceId] else { continue }
            let frame = PanelPlacementPolicy.barFrame(
                for: geometry,
                area: newValue,
                barHeight: barHeight
            )
            panel.setFrame(frame, display: true)
        }

        if autoHideEnabled {
            updateAutoHideForMouseLocation()
        }
    }

    // MARK: - Auto Hide

    private func contextMenuTrackingDidChange(_ isTracking: Bool, for spaceId: Int) {
        if isTracking {
            contextMenuTrackingSpaces.insert(spaceId)
            cancelPendingAutoHideTransition(for: spaceId)
        } else {
            contextMenuTrackingSpaces.remove(spaceId)
            updateAutoHideForMouseLocation()
        }
    }

    private func toggleAutoHide() {
        UserDefaults.standard.set(
            !autoHideEnabled,
            forKey: AppSettings.autoHideEnabledKey
        )
        refreshAutoHideSettings()
    }

    private func navigationModifiersDidChange(_ areHeld: Bool) {
        guard areHeld != navigationModifiersHeld else { return }
        navigationModifiersHeld = areHeld

        guard autoHideEnabled else { return }

        if areHeld {
            for spaceId in panels.keys where !fullscreenHiddenSpaces.contains(spaceId) {
                cancelPendingAutoHideTransition(for: spaceId)
                setAutoHideShown(true, for: spaceId, animated: true)
            }
        } else {
            updateAutoHideForMouseLocation(hideImmediatelyWhenInactive: true)
        }
    }

    private func refreshAutoHideSettings() {
        let defaults = UserDefaults.standard
        let newEnabledValue = defaults.bool(forKey: AppSettings.autoHideEnabledKey)
        let storedActivationHeight = defaults.object(
            forKey: AppSettings.autoHideActivationHeightKey
        ) as? Double ?? AppSettings.defaultAutoHideActivationHeight
        let newActivationHeight = CGFloat(min(
            max(storedActivationHeight, AppSettings.autoHideActivationHeightRange.lowerBound),
            AppSettings.autoHideActivationHeightRange.upperBound
        ))
        let enabledChanged = newEnabledValue != autoHideEnabled
        let activationHeightChanged = newActivationHeight != autoHideActivationHeight

        guard enabledChanged || activationHeightChanged else { return }

        autoHideEnabled = newEnabledValue
        autoHideActivationHeight = newActivationHeight
        cancelAllPendingAutoHideTransitions()

        if enabledChanged && newEnabledValue {
            for spaceId in panels.keys {
                setAutoHideShown(false, for: spaceId, animated: true)
            }
            if isTrackerStarted {
                startAutoHideTracking()
            }
        } else if enabledChanged {
            stopAutoHideTracking()
            for spaceId in panels.keys where !fullscreenHiddenSpaces.contains(spaceId) {
                setAutoHideShown(true, for: spaceId, animated: true)
            }
        } else if newEnabledValue {
            updateAutoHideForMouseLocation()
        }
    }

    private func startAutoHideTracking() {
        guard autoHideTimer == nil else { return }

        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateAutoHideForMouseLocation()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoHideTimer = timer
        updateAutoHideForMouseLocation()
    }

    private func stopAutoHideTracking() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        cancelAllPendingAutoHideTransitions()
    }

    private func updateAutoHideForMouseLocation(
        hideImmediatelyWhenInactive: Bool = false
    ) {
        guard autoHideEnabled else { return }
        let mouseLocation = NSEvent.mouseLocation

        for spaceId in panels.keys {
            guard !contextMenuTrackingSpaces.contains(spaceId) else {
                cancelPendingAutoHideTransition(for: spaceId)
                continue
            }

            guard !fullscreenHiddenSpaces.contains(spaceId),
                  let geometry = panelScreenGeometries[spaceId] else {
                cancelPendingAutoHideTransition(for: spaceId)
                continue
            }

            let activationFrame = PanelPlacementPolicy.placementFrame(
                for: geometry,
                area: barPlacementArea
            )
            let isShown = autoHideShownStates[spaceId] ?? false
            let mouseRequestsReveal = AutoHidePolicy.shouldShowBar(
                mouseLocation: mouseLocation,
                screenFrame: activationFrame,
                barHeight: barHeight,
                activationHeight: autoHideActivationHeight,
                isBarShown: isShown
            )

            if navigationModifiersHeld {
                cancelPendingAutoHideTransition(for: spaceId)
                setAutoHideShown(true, for: spaceId, animated: true)
            } else if hideImmediatelyWhenInactive && !mouseRequestsReveal {
                cancelPendingAutoHideTransition(for: spaceId)
                setAutoHideShown(false, for: spaceId, animated: true)
            } else {
                requestAutoHideState(mouseRequestsReveal, for: spaceId)
            }
        }
    }

    private func requestAutoHideState(_ shown: Bool, for spaceId: Int) {
        if pendingAutoHideTargets[spaceId] == shown {
            return
        }

        cancelPendingAutoHideTransition(for: spaceId)

        guard autoHideShownStates[spaceId] != shown else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingAutoHideTransitions.removeValue(forKey: spaceId)
            self.pendingAutoHideTargets.removeValue(forKey: spaceId)

            guard self.autoHideEnabled,
                  !self.fullscreenHiddenSpaces.contains(spaceId),
                  !self.contextMenuTrackingSpaces.contains(spaceId) else {
                return
            }
            self.setAutoHideShown(shown, for: spaceId, animated: true)
        }

        pendingAutoHideTransitions[spaceId] = workItem
        pendingAutoHideTargets[spaceId] = shown
        let delay = shown ? AutoHidePolicy.revealDelay : AutoHidePolicy.hideDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func setAutoHideShown(_ shown: Bool, for spaceId: Int, animated: Bool) {
        guard let contentView = panels[spaceId]?.contentView as? MacsBarPanelContentView else {
            return
        }

        autoHideShownStates[spaceId] = shown
        contentView.setBarShown(shown, animated: animated)
    }

    private var auxiliaryWindows: [NSWindow] {
        [NSApp.settingsWindow, welcomeGuideController.window].compactMap { $0 }
    }

    private func cancelPendingAutoHideTransition(for spaceId: Int) {
        pendingAutoHideTransitions.removeValue(forKey: spaceId)?.cancel()
        pendingAutoHideTargets.removeValue(forKey: spaceId)
    }

    private func cancelAllPendingAutoHideTransitions() {
        for workItem in pendingAutoHideTransitions.values {
            workItem.cancel()
        }
        pendingAutoHideTransitions.removeAll()
        pendingAutoHideTargets.removeAll()
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
