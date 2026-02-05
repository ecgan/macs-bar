import AppKit
import SwiftUI

/// Manages the Settings window for LSUIElement apps where SwiftUI Settings scene doesn't work reliably
class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func showSettings() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Macs Bar Settings"
        window.contentViewController = hostingController
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = WindowDelegate.shared

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose() {
        window = nil
    }
}

private class WindowDelegate: NSObject, NSWindowDelegate {
    static let shared = WindowDelegate()

    func windowWillClose(_ notification: Notification) {
        SettingsWindowController.shared.windowWillClose()
    }
}
