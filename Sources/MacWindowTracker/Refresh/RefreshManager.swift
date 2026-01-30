import AppKit
import Combine

/// Events that can trigger a refresh
public enum RefreshEvent: Sendable, Equatable {
    case axNotification(String)
    case appLaunch
    case appTerminate
    case appActivate
    case spaceChange
    case mouseClick
    case timer
    case manual
}

/// Manages refresh scheduling with debouncing.
/// Implements AeroSpace's hybrid approach: AX notifications as hints + periodic polling.
@MainActor
final class RefreshManager {
    private var refreshTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var mouseMonitor: Any?
    private var workspaceObservers: [Any] = []

    private let onRefresh: @MainActor (RefreshEvent) async -> Void
    private let debounceInterval: Duration

    /// Create a refresh manager
    /// - Parameters:
    ///   - debounceInterval: Minimum time between refreshes (default 50ms)
    ///   - onRefresh: Callback invoked when refresh should occur
    init(
        debounceInterval: Duration = .milliseconds(50),
        onRefresh: @escaping @MainActor (RefreshEvent) async -> Void
    ) {
        self.debounceInterval = debounceInterval
        self.onRefresh = onRefresh
    }

    /// Start the refresh manager with all event sources
    func start() {
        setupWorkspaceObservers()
        setupMouseMonitor()
        startPeriodicTimer()
    }

    /// Stop the refresh manager
    func stop() {
        refreshTask?.cancel()
        refreshTask = nil

        timerTask?.cancel()
        timerTask = nil

        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }

        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    /// Schedule a refresh with debouncing
    func scheduleRefresh(_ event: RefreshEvent) {
        // Cancel any pending refresh
        refreshTask?.cancel()

        // Schedule new refresh after debounce interval
        refreshTask = Task { [debounceInterval, onRefresh] in
            do {
                try await Task.sleep(for: debounceInterval)
                await onRefresh(event)
            } catch {
                // Cancelled, ignore
            }
        }
    }

    /// Trigger an immediate refresh (bypasses debouncing)
    func refreshNow(_ event: RefreshEvent) {
        refreshTask?.cancel()
        refreshTask = Task { [onRefresh] in
            await onRefresh(event)
        }
    }

    private func setupWorkspaceObservers() {
        let nc = NSWorkspace.shared.notificationCenter

        // App activation - important for focus tracking
        workspaceObservers.append(
            nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleRefresh(.appActivate) }
            }
        )

        // App launch
        workspaceObservers.append(
            nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleRefresh(.appLaunch) }
            }
        )

        // App termination
        workspaceObservers.append(
            nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleRefresh(.appTerminate) }
            }
        )

        // Space change - bypass debounce for instant cache swap
        workspaceObservers.append(
            nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshNow(.spaceChange) }
            }
        )

        // App hide/unhide
        workspaceObservers.append(
            nc.addObserver(forName: NSWorkspace.didHideApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleRefresh(.appActivate) }
            }
        )
        workspaceObservers.append(
            nc.addObserver(forName: NSWorkspace.didUnhideApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleRefresh(.appActivate) }
            }
        )
    }

    private func setupMouseMonitor() {
        // Mouse click fallback - "Yes, kAXUIElementDestroyedNotification is that unreliable"
        // This catches window closes, focus changes, etc. that AX might miss
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleRefresh(.mouseClick)
            }
        }
    }

    private func startPeriodicTimer() {
        // Periodic refresh as safety net (every 2 seconds)
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                self?.scheduleRefresh(.timer)
            }
        }
    }
}
