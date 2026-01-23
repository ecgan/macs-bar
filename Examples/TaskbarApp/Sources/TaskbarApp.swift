import SwiftUI
import MacWindowTracker

@main
struct TaskbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty scene - we use the menu bar only
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var windowTracker: WindowTracker?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - this is a menu bar app
        NSApp.setActivationPolicy(.accessory)

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: "Window Taskbar")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 300)
        popover.behavior = .transient
        popover.animates = true

        let tracker = WindowTracker()
        let contentView = TaskbarContentView(tracker: tracker)
        popover.contentViewController = NSHostingController(rootView: contentView)

        self.popover = popover
        self.windowTracker = tracker

        // Start tracking
        Task {
            do {
                try await tracker.start()
            } catch WindowTrackerError.accessibilityPermissionDenied {
                print("Please grant Accessibility permission in System Preferences > Privacy & Security > Accessibility")
            } catch {
                print("Failed to start window tracker: \(error)")
            }
        }
    }

    @objc func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Activate app to ensure popover gets focus
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
