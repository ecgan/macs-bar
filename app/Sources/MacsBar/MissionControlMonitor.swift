import AppKit
import ApplicationServices

enum MissionControlState: String {
    case showDesktop = "AXExposeShowDesktop"
    case inactive = "AXExposeExit"
}

private let dockBundleIdentifier = "com.apple.dock"

@MainActor
final class MissionControlMonitor {
    var onShowDesktopChanged: ((Bool) -> Void)?

    private var dockElement: AXUIElement?
    private var dockProcessIdentifier: pid_t?
    private var observer: AXObserver?
    private var registeredNotifications: [CFString] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isStarted = false
    private(set) var isShowDesktopActive = false

    func start() {
        guard !isStarted else { return }
        isStarted = true

        let notificationCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let dock = notification.userInfo?[
                    NSWorkspace.applicationUserInfoKey
                ] as? NSRunningApplication,
                      dock.bundleIdentifier == dockBundleIdentifier else {
                    return
                }
                Task { @MainActor [weak self] in
                    self?.dockDidLaunch(dock)
                }
            }
        )
        workspaceObservers.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let dock = notification.userInfo?[
                    NSWorkspace.applicationUserInfoKey
                ] as? NSRunningApplication,
                      dock.bundleIdentifier == dockBundleIdentifier else {
                    return
                }
                Task { @MainActor [weak self] in
                    self?.dockDidTerminate(dock)
                }
            }
        )

        guard let dock = NSRunningApplication.runningApplications(
            withBundleIdentifier: dockBundleIdentifier
        ).first else {
            NSLog("[MacsBar] MissionControlMonitor: Dock process not found")
            return
        }
        attach(to: dock)
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false

        let notificationCenter = NSWorkspace.shared.notificationCenter
        for workspaceObserver in workspaceObservers {
            notificationCenter.removeObserver(workspaceObserver)
        }
        workspaceObservers.removeAll()
        detachDockObserver()
        isShowDesktopActive = false
    }

    private func attach(to dock: NSRunningApplication) {
        guard observer == nil else { return }
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
        var newRegisteredNotifications: [CFString] = []

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
                for registeredNotification in newRegisteredNotifications {
                    AXObserverRemoveNotification(
                        newObserver,
                        element,
                        registeredNotification
                    )
                }
                return
            }
            newRegisteredNotifications.append(notification)
        }

        dockElement = element
        dockProcessIdentifier = dock.processIdentifier
        observer = newObserver
        registeredNotifications = newRegisteredNotifications
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(newObserver),
            .commonModes
        )
    }

    private func detachDockObserver() {
        if let observer, let dockElement {
            for notification in registeredNotifications {
                AXObserverRemoveNotification(observer, dockElement, notification)
            }
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }

        registeredNotifications.removeAll()
        self.observer = nil
        self.dockElement = nil
        dockProcessIdentifier = nil
    }

    private func dockDidLaunch(_ dock: NSRunningApplication) {
        guard isStarted else { return }
        guard dock.processIdentifier != dockProcessIdentifier else { return }

        detachDockObserver()
        setShowDesktopActive(false)
        attach(to: dock)
    }

    private func dockDidTerminate(_ dock: NSRunningApplication) {
        guard isStarted, dock.processIdentifier == dockProcessIdentifier else { return }

        detachDockObserver()
        setShowDesktopActive(false)
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
