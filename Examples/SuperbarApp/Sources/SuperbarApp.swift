import SwiftUI
import Combine
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
    var panel: NSPanel?
    var windowTracker: WindowTracker?
    private var windowsCancellable: AnyCancellable?

    private let barHeight: CGFloat = 40

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let tracker = WindowTracker()
        self.windowTracker = tracker

        createSuperbarPanel(tracker: tracker)
        observeMaximizedWindows(tracker: tracker)

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

    private func observeMaximizedWindows(tracker: WindowTracker) {
        windowsCancellable = tracker.$windows
            .sink { [weak self] windows in
                guard let self else { return }
                self.adjustMaximizedWindows(windows, tracker: tracker)
            }
    }

    private func adjustMaximizedWindows(_ windows: [TrackedWindow], tracker: WindowTracker) {
        guard let mainMonitor = tracker.monitors.first(where: { $0.isMain }) else { return }

        let menuBarHeight = mainMonitor.visibleFrame.origin.y
        let expectedMaxHeight = mainMonitor.frame.height - menuBarHeight
        let superbarTop = mainMonitor.frame.maxY - barHeight
        let tolerance: CGFloat = 2

        for window in windows {
            // Only check windows on the main monitor
            guard window.monitorId == mainMonitor.id else { continue }

            // Check if window size matches maximized (screen width × screen height minus menu bar)
            let widthMatches = abs(window.frame.width - mainMonitor.frame.width) <= tolerance
            let heightMatches = abs(window.frame.height - expectedMaxHeight) <= tolerance
            guard widthMatches && heightMatches else { continue }

            // Check if it overlaps with the superbar
            guard window.frame.maxY > superbarTop else { continue }

            // Resize to avoid superbar overlap
            let newHeight = expectedMaxHeight - barHeight
            tracker.resizeWindow(window, to: CGSize(width: window.frame.width, height: newHeight))
        }
    }

    @objc private func screenDidChange() {
        guard let panel = panel, let screen = NSScreen.main else { return }
        let newFrame = NSRect(
            x: screen.frame.origin.x,
            y: screen.frame.origin.y,
            width: screen.frame.width,
            height: barHeight
        )
        panel.setFrame(newFrame, display: true)
    }
}
