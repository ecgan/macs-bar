import AppKit
import ApplicationServices

enum MissionControlState: String {
    case showDesktop = "AXExposeShowDesktop"
    case inactive = "AXExposeExit"
}

@MainActor
final class MissionControlMonitor {
    var onShowDesktopChanged: ((Bool) -> Void)?

    private var dockElement: AXUIElement?
    private var observer: AXObserver?
    private var registeredNotifications: [CFString] = []
    private(set) var isShowDesktopActive = false

    func start() {
        guard observer == nil else { return }
        guard let dock = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.dock"
        ).first else {
            NSLog("[MacsBar] MissionControlMonitor: Dock process not found")
            return
        }

        let element = AXUIElementCreateApplication(dock.processIdentifier)
        var newObserver: AXObserver?
        let createResult = AXObserverCreate(
            dock.processIdentifier,
            missionControlObserverCallback,
            &newObserver
        )

        guard createResult == .success, let newObserver else {
            NSLog(
                "[MacsBar] MissionControlMonitor: failed to create Dock observer "
                    + "(\(createResult.rawValue))"
            )
            return
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let notifications = [
            MissionControlState.showDesktop.rawValue as CFString,
            MissionControlState.inactive.rawValue as CFString,
        ]

        for notification in notifications {
            let result = AXObserverAddNotification(
                newObserver,
                element,
                notification,
                refcon
            )
            guard result == .success || result == .notificationAlreadyRegistered else {
                NSLog(
                    "[MacsBar] MissionControlMonitor: failed to register "
                        + "\(notification) (\(result.rawValue))"
                )
                for registeredNotification in registeredNotifications {
                    AXObserverRemoveNotification(
                        newObserver,
                        element,
                        registeredNotification
                    )
                }
                registeredNotifications.removeAll()
                return
            }
            registeredNotifications.append(notification)
        }

        dockElement = element
        observer = newObserver
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(newObserver),
            .commonModes
        )
    }

    func stop() {
        guard let observer, let dockElement else { return }

        for notification in registeredNotifications {
            AXObserverRemoveNotification(observer, dockElement, notification)
        }
        registeredNotifications.removeAll()
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )

        self.observer = nil
        self.dockElement = nil
        isShowDesktopActive = false
    }

    fileprivate func handle(notificationName: String) {
        guard let state = MissionControlState(rawValue: notificationName) else { return }

        switch state {
        case .showDesktop:
            setShowDesktopActive(true)
        case .inactive:
            setShowDesktopActive(false)
        }
    }

    private func setShowDesktopActive(_ active: Bool) {
        guard active != isShowDesktopActive else { return }
        isShowDesktopActive = active
        onShowDesktopChanged?(active)
    }
}

private let missionControlObserverCallback: AXObserverCallback = {
    _,
    _,
    notification,
    refcon in
    guard let refcon else { return }
    let monitor = Unmanaged<MissionControlMonitor>
        .fromOpaque(refcon)
        .takeUnretainedValue()
    let notificationName = notification as String

    // This observer source is installed on the main run loop, so handle the event
    // immediately instead of adding another main-actor scheduling hop.
    MainActor.assumeIsolated {
        monitor.handle(notificationName: notificationName)
    }
}
