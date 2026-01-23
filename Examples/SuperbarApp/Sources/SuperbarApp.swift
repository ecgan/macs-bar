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

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel?
    var windowTracker: WindowTracker?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let tracker = WindowTracker()
        self.windowTracker = tracker

        createSuperbarPanel(tracker: tracker)

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

    private func createSuperbarPanel(tracker: WindowTracker) {
        guard let screen = NSScreen.main else { return }

        let barHeight: CGFloat = 40
        let barFrame = NSRect(
            x: screen.frame.origin.x,
            y: screen.frame.origin.y,
            width: screen.frame.width,
            height: barHeight
        )

        let panel = NSPanel(
            contentRect: barFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]

        let contentView = SuperbarContentView(tracker: tracker)
        let hostingView = NSHostingView(rootView: contentView)
        panel.contentView = hostingView

        panel.orderFrontRegardless()
        self.panel = panel
    }

    @objc private func screenDidChange() {
        guard let panel = panel, let screen = NSScreen.main else { return }
        let barHeight: CGFloat = 40
        let newFrame = NSRect(
            x: screen.frame.origin.x,
            y: screen.frame.origin.y,
            width: screen.frame.width,
            height: barHeight
        )
        panel.setFrame(newFrame, display: true)
    }
}
