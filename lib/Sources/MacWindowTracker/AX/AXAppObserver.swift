import AppKit
@preconcurrency import ApplicationServices

/// Callback invoked when an AX notification is received
public typealias AXNotificationHandler = @MainActor @Sendable (AXNotification) -> Void

/// Represents an AX notification event
public struct AXNotification: Sendable {
    public let appPid: pid_t
    public let appBundleId: String?
    public let notificationName: String
    public let windowId: CGWindowID?
}

/// Observes accessibility notifications for a single application.
/// Each app gets its own dedicated thread with a CFRunLoop for AX operations.
/// Inspired by AeroSpace's per-app thread architecture.
final class AXAppObserver: @unchecked Sendable {
    let pid: pid_t
    let bundleId: String?
    private let axApp: AXUIElement
    private var thread: Thread?
    private var subscriptions: [AXSubscription] = []
    private let onNotification: AXNotificationHandler

    /// Create an observer for an application
    init(app: NSRunningApplication, onNotification: @escaping AXNotificationHandler) {
        self.pid = app.processIdentifier
        self.bundleId = app.bundleIdentifier
        self.axApp = AXUIElement.application(pid: pid)
        self.onNotification = onNotification
    }

    /// Start observing AX notifications for this app
    func start() {
        let thread = Thread { [weak self] in
            self?.runLoop()
        }
        thread.name = "AXAppObserver-\(pid)"
        thread.start()
        self.thread = thread
    }

    /// Stop observing and clean up
    func stop() {
        thread?.cancel()
        thread = nil
    }

    private func runLoop() {
        // Set up AX observer subscriptions on this thread
        let handlers: HandlerToNotifKeyMapping = [
            (Self.axCallback, [
                kAXWindowCreatedNotification,
                kAXFocusedWindowChangedNotification,
                kAXUIElementDestroyedNotification,
                kAXWindowMiniaturizedNotification,
                kAXWindowDeminiaturizedNotification,
                kAXWindowResizedNotification,
                kAXWindowMovedNotification,
            ])
        ]

        subscriptions = AXSubscription.bulkSubscribe(
            pid: pid,
            element: axApp,
            thread: Thread.current,
            handlers: handlers
        )

        // Store self reference for the callback
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for subscription in subscriptions {
            // Re-add with refcon so callback can find us
            for key in subscription.notificationKeys {
                AXObserverRemoveNotification(subscription.observer, axApp, key as CFString)
                AXObserverAddNotification(subscription.observer, axApp, key as CFString, refcon)
            }
        }

        // Run the run loop until cancelled
        while !Thread.current.isCancelled {
            CFRunLoopRunInMode(.defaultMode, 1.0, true)
        }

        // Clean up subscriptions
        subscriptions.removeAll()
    }

    /// Static callback that receives AX notifications
    private static let axCallback: AXObserverCallback = { _, element, notification, refcon in
        guard let refcon else { return }
        let observer = Unmanaged<AXAppObserver>.fromOpaque(refcon).takeUnretainedValue()

        let notificationName = notification as String
        let windowId = element.windowId()

        let event = AXNotification(
            appPid: observer.pid,
            appBundleId: observer.bundleId,
            notificationName: notificationName,
            windowId: windowId
        )

        // Dispatch to main actor
        Task { @MainActor in
            observer.onNotification(event)
        }
    }

    /// Get the focused window for this app
    func getFocusedWindow() async throws -> (windowId: CGWindowID, element: AXUIElement)? {
        guard let thread else { return nil }

        return try await thread.runInLoop { _ in
            self.axApp.focusedWindow()
        }
    }
}

// MARK: - App Observer Manager

/// Manages AX observers for all running applications
@MainActor
final class AppObserverManager {
    private var observers: [pid_t: AXAppObserver] = [:]
    private let onNotification: AXNotificationHandler
    private var workspaceObservers: [Any] = []

    init(onNotification: @escaping AXNotificationHandler) {
        self.onNotification = onNotification
    }

    /// Start observing all observable applications.
    /// See `NSRunningApplication.isObservable` for the filtering criteria.
    func start() {
        // Observe existing apps
        for app in NSWorkspace.shared.runningApplications {
            guard app.isObservable else { continue }
            addObserver(for: app)
        }

        // Listen for app launches and terminations
        let nc = NSWorkspace.shared.notificationCenter

        workspaceObservers.append(
            nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.isObservable else { return }
                Task { @MainActor in self?.addObserver(for: app) }
            }
        )

        workspaceObservers.append(
            nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                Task { @MainActor in self?.removeObserver(for: app.processIdentifier) }
            }
        )
    }

    /// Stop all observers
    func stop() {
        for observer in observers.values {
            observer.stop()
        }
        observers.removeAll()

        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    /// Get the focused window of the frontmost app.
    /// Uses the app's observer if available, otherwise falls back to direct AX query.
    /// This allows focus detection for accessory apps without dedicated observers.
    func getFocusedWindow() async throws -> (pid: pid_t, windowId: CGWindowID)? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let pid = frontApp.processIdentifier

        // Try observer first (faster, uses dedicated thread)
        if let observer = observers[pid] {
            if let (windowId, _) = try await observer.getFocusedWindow() {
                return (pid, windowId)
            }
        }

        // Fallback: direct AX query for apps without observers (e.g., accessory apps)
        let axApp = AXUIElement.application(pid: pid)
        if let (windowId, _) = axApp.focusedWindow() {
            return (pid, windowId)
        }

        return nil
    }

    private func addObserver(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard observers[pid] == nil else { return }

        let observer = AXAppObserver(app: app, onNotification: onNotification)
        observer.start()
        observers[pid] = observer
    }

    private func removeObserver(for pid: pid_t) {
        observers[pid]?.stop()
        observers[pid] = nil
    }
}
