import AppKit
import ApplicationServices

/// Callback type for AX notifications
public typealias AXObserverCallback = @convention(c) (
    AXObserver,
    AXUIElement,
    CFString,
    UnsafeMutableRawPointer?
) -> Void

/// Mapping of notification handlers to their notification keys
public typealias HandlerToNotifKeyMapping = [(AXObserverCallback, [String])]

/// Manages AX notification subscriptions with automatic cleanup.
/// The subscription is active as long as you keep this instance in memory.
/// When deallocated, it automatically removes the observer from the run loop
/// and unsubscribes from all notifications.
///
/// Inspired by AeroSpace's AxSubscription pattern.
final class AXSubscription {
    let observer: AXObserver
    let element: AXUIElement
    private(set) var notificationKeys: Set<String> = []
    private let thread: Thread

    private init(observer: AXObserver, element: AXUIElement, thread: Thread) {
        self.observer = observer
        self.element = element
        self.thread = thread
    }

    /// Subscribe to a notification. Returns true on success.
    private func subscribe(_ key: String) -> Bool {
        let result = AXObserverAddNotification(observer, element, key as CFString, nil)
        if result == .success {
            notificationKeys.insert(key)
            return true
        }
        return false
    }

    /// Create subscriptions for an app with multiple handlers and notification keys.
    /// Returns empty array if any subscription fails.
    static func bulkSubscribe(
        pid: pid_t,
        element: AXUIElement,
        thread: Thread,
        handlers: HandlerToNotifKeyMapping
    ) -> [AXSubscription] {
        var result: [AXSubscription] = []
        var visitedKeys: Set<String> = []

        for (handler, notifKeys) in handlers {
            guard let obs = createObserver(pid: pid, handler: handler) else {
                return []
            }

            let subscription = AXSubscription(observer: obs, element: element, thread: thread)

            for key in notifKeys {
                assert(visitedKeys.insert(key).inserted, "Duplicate notification key: \(key)")
                if !subscription.subscribe(key) {
                    return []
                }
            }

            // Add the observer's run loop source to the current run loop
            CFRunLoopAddSource(
                CFRunLoopGetCurrent(),
                AXObserverGetRunLoopSource(obs),
                .defaultMode
            )
            result.append(subscription)
        }

        return result
    }

    /// Create a single subscription for specific notifications
    static func subscribe(
        pid: pid_t,
        element: AXUIElement,
        thread: Thread,
        handler: AXObserverCallback,
        notifications: [String]
    ) -> AXSubscription? {
        let subscriptions = bulkSubscribe(
            pid: pid,
            element: element,
            thread: thread,
            handlers: [(handler, notifications)]
        )
        return subscriptions.first
    }

    private static func createObserver(pid: pid_t, handler: AXObserverCallback) -> AXObserver? {
        var observer: AXObserver?
        let result = AXObserverCreate(pid, handler, &observer)
        return result == .success ? observer : nil
    }

    deinit {
        // Remove from run loop and unsubscribe from all notifications
        // This must be done on the same thread where the subscription was created
        CFRunLoopRemoveSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        for key in notificationKeys {
            AXObserverRemoveNotification(observer, element, key as CFString)
        }
    }
}
