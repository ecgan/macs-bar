import AppKit
import Combine

/// Manages monitor/display detection and window-to-monitor mapping.
/// Follows AeroSpace's pattern of detecting main monitor by frame position
/// rather than trusting NSScreen.main (which is unreliable in notification callbacks).
@MainActor
public final class MonitorManager: ObservableObject {
    @Published public private(set) var monitors: [TrackedMonitor] = []

    // Use nonisolated(unsafe) to allow access in deinit
    nonisolated(unsafe) private var screenChangeObserver: Any?

    public init() {
        refresh()
        setupObserver()
    }

    deinit {
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Refresh the list of monitors from NSScreen
    public func refresh() {
        monitors = NSScreen.screens.enumerated().map { index, screen in
            TrackedMonitor(
                id: index + 1, // 1-based index like AeroSpace
                name: screen.localizedName,
                frame: screen.frame.normalized(),
                visibleFrame: screen.visibleFrame.normalized(),
                isMain: screen.isMainScreen
            )
        }
    }

    /// Get the main monitor (the one with the menu bar)
    public var mainMonitor: TrackedMonitor? {
        monitors.first { $0.isMain } ?? monitors.first
    }

    /// Get monitors sorted by position (left to right, top to bottom)
    public var sortedMonitors: [TrackedMonitor] {
        monitors.sorted { lhs, rhs in
            if lhs.frame.minX != rhs.frame.minX {
                return lhs.frame.minX < rhs.frame.minX
            }
            return lhs.frame.minY < rhs.frame.minY
        }
    }

    /// Find the monitor that contains a given point
    public func monitor(containing point: CGPoint) -> TrackedMonitor? {
        monitors.first { $0.frame.contains(point) }
    }

    /// Find the monitor that best matches a window's frame.
    /// Returns the monitor that contains the window's center,
    /// or the closest monitor if the center is off-screen.
    public func monitor(forWindowFrame frame: CGRect) -> TrackedMonitor? {
        let center = CGPoint(x: frame.midX, y: frame.midY)

        // First try to find monitor containing the center
        if let monitor = monitor(containing: center) {
            return monitor
        }

        // Fall back to closest monitor by distance
        return monitors.min { lhs, rhs in
            distance(from: center, to: lhs.frame) < distance(from: center, to: rhs.frame)
        }
    }

    /// Get the monitor ID for a window frame
    public func monitorId(forWindowFrame frame: CGRect) -> Int {
        monitor(forWindowFrame: frame)?.id ?? 1
    }

    private func setupObserver() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    /// Calculate the distance from a point to a rectangle
    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return sqrt(dx * dx + dy * dy)
    }
}

// MARK: - NSScreen Extensions

private extension NSScreen {
    /// The main screen is the one at origin (0, 0).
    /// We don't use NSScreen.main because it's unreliable in notification callbacks.
    var isMainScreen: Bool {
        frame.minX == 0 && frame.minY == 0
    }
}

// MARK: - CGRect Normalization

private extension CGRect {
    /// Convert a screen frame from AppKit coordinates (origin at bottom-left of main screen,
    /// Y increases upward) to Core Graphics coordinates (origin at top-left of main screen,
    /// Y increases downward). This matches how CGWindowListCopyWindowInfo reports window positions.
    func normalized() -> CGRect {
        guard let mainScreen = NSScreen.screens.first else { return self }
        let mainHeight = mainScreen.frame.height
        // In CG coords, the Y origin is flipped: cgY = mainHeight - appkitY - rectHeight
        return CGRect(
            x: self.origin.x,
            y: mainHeight - self.origin.y - self.height,
            width: self.width,
            height: self.height
        )
    }
}
