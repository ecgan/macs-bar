import AppKit
import SwiftUI

@MainActor
final class WelcomeGuideController: NSObject, ObservableObject, NSWindowDelegate {
    private let permissionManager: AccessibilityPermissionManager
    private let shortcutStorage: ShortcutStorage
    private let state: WelcomeGuideState
    private var windowController: NSWindowController?

    var window: NSWindow? {
        windowController?.window
    }

    init(
        permissionManager: AccessibilityPermissionManager,
        shortcutStorage: ShortcutStorage,
        defaults: UserDefaults = .standard
    ) {
        self.permissionManager = permissionManager
        self.shortcutStorage = shortcutStorage
        self.state = WelcomeGuideState(defaults: defaults)
        super.init()
    }

    func shouldPresentAutomatically() -> Bool {
        state.shouldPresentAutomatically(
            accessibilityGranted: permissionManager.isPermissionGranted
        )
    }

    func show(isFirstRun: Bool = false) {
        if windowController == nil {
            windowController = makeWindowController(isFirstRun: isFirstRun)
        }

        guard let window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func finish() {
        state.markCompleted()
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Closing the window is equivalent to skipping. The guide remains
        // available from the menu and General settings.
        state.markCompleted()
        windowController = nil
    }

    private func makeWindowController(isFirstRun: Bool) -> NSWindowController {
        let rootView = WelcomeGuideView(
            isFirstRun: isFirstRun,
            onFinish: { [weak self] in
                self?.finish()
            }
        )
        .environmentObject(permissionManager)
        .environmentObject(shortcutStorage)

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Macs Bar"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.delegate = self
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        return NSWindowController(window: window)
    }
}
