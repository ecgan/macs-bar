import Combine
import CoreGraphics
import MacWindowTracker

@MainActor
class SpaceBarState: ObservableObject {
    let spaceId: Int
    @Published var windows: [TrackedWindow] = []
    @Published private(set) var pillWidth: CGFloat = 0
    @Published private(set) var presentation: BarPresentation = .hidden

    private static let focusLossGracePeriod: Duration = .milliseconds(200)
    private static let collapseDelay: Duration = .milliseconds(500)

    private let onActivate: (TrackedWindow) async -> Void
    private let onClose: (TrackedWindow) -> Void
    private var visibilityMode = BarVisibilityMode.current()
    private var screenFrame: CGRect = .zero
    private var focusedWindowFrame: CGRect?
    private var isFullscreenSuppressed = false
    private var focusedWindowOverlapsPill = false
    private var focusLossHasSettled = false
    private var hoveredTargets: Set<BarHoverTarget> = []
    private var focusLossTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var isCollapsePending = false

    init(
        spaceId: Int,
        onActivate: @escaping @MainActor (TrackedWindow) async -> Void,
        onClose: @escaping @MainActor (TrackedWindow) -> Void
    ) {
        self.spaceId = spaceId
        self.onActivate = onActivate
        self.onClose = onClose
    }

    func updateContext(
        windows: [TrackedWindow],
        screenFrame: CGRect,
        focusedWindowFrame: CGRect?,
        visibilityMode: BarVisibilityMode,
        isFullscreenSuppressed: Bool
    ) {
        self.windows = windows
        self.screenFrame = screenFrame
        self.visibilityMode = visibilityMode
        self.isFullscreenSuppressed = isFullscreenSuppressed

        if isFullscreenSuppressed {
            hoveredTargets.removeAll()
            cancelCollapseTask()
            cancelFocusLossTask()
            reconcilePresentation()
            return
        }

        guard !windows.isEmpty else {
            hoveredTargets.removeAll()
            cancelCollapseTask()
            cancelFocusLossTask()
            self.focusedWindowFrame = nil
            focusedWindowOverlapsPill = false
            focusLossHasSettled = true
            reconcilePresentation()
            return
        }

        updateFocusedWindowFrame(focusedWindowFrame)
        reconcilePresentation()
    }

    func setVisibilityMode(_ mode: BarVisibilityMode) {
        visibilityMode = mode
        reconcilePresentation()
    }

    func updatePillWidth(_ width: CGFloat) {
        guard width > 0, abs(width - pillWidth) > 0.5 else { return }
        pillWidth = width
        reevaluateOverlap()
        reconcilePresentation()
    }

    func setHovering(_ isHovering: Bool, target: BarHoverTarget) {
        if isHovering {
            hoveredTargets.insert(target)
        } else {
            hoveredTargets.remove(target)
        }

        if !hoveredTargets.isEmpty {
            cancelCollapseTask()
            reconcilePresentation()
            return
        }

        let presentationWithoutPointer = BarVisibilityPolicy.presentation(
            mode: visibilityMode,
            isFullscreenSuppressed: isFullscreenSuppressed,
            hasWindows: !windows.isEmpty,
            focusedWindowOverlapsPill: focusedWindowOverlapsPill,
            isPointerInside: false
        )

        guard presentation == .expanded, presentationWithoutPointer == .collapsed else {
            reconcilePresentation()
            return
        }

        scheduleCollapse()
    }

    func activateWindow(_ window: TrackedWindow) async {
        await onActivate(window)
    }

    func closeWindow(_ window: TrackedWindow) {
        onClose(window)
    }

    private func updateFocusedWindowFrame(_ frame: CGRect?) {
        guard let frame else {
            guard !focusLossHasSettled, focusLossTask == nil else { return }
            focusLossTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: Self.focusLossGracePeriod)
                } catch {
                    return
                }
                guard let self else { return }
                focusLossTask = nil
                focusLossHasSettled = true
                focusedWindowFrame = nil
                focusedWindowOverlapsPill = false
                reconcilePresentation()
            }
            return
        }

        cancelFocusLossTask()
        focusLossHasSettled = false
        focusedWindowFrame = frame
        reevaluateOverlap()
    }

    private func reevaluateOverlap() {
        guard let focusedWindowFrame else {
            focusedWindowOverlapsPill = false
            return
        }
        focusedWindowOverlapsPill = BarGeometry.window(
            focusedWindowFrame,
            overlapsCanonicalPillOn: screenFrame,
            pillWidth: pillWidth
        )
    }

    private func reconcilePresentation() {
        var desiredPresentation = BarVisibilityPolicy.presentation(
            mode: visibilityMode,
            isFullscreenSuppressed: isFullscreenSuppressed,
            hasWindows: !windows.isEmpty,
            focusedWindowOverlapsPill: focusedWindowOverlapsPill,
            isPointerInside: !hoveredTargets.isEmpty
        )

        if desiredPresentation == .collapsed,
           isCollapsePending,
           presentation == .expanded {
            desiredPresentation = .expanded
        } else if desiredPresentation != .collapsed {
            cancelCollapseTask()
        }

        presentation = desiredPresentation
    }

    private func scheduleCollapse() {
        cancelCollapseTask()
        isCollapsePending = true
        collapseTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.collapseDelay)
            } catch {
                return
            }
            guard let self else { return }
            collapseTask = nil
            isCollapsePending = false
            reconcilePresentation()
        }
    }

    private func cancelFocusLossTask() {
        focusLossTask?.cancel()
        focusLossTask = nil
    }

    private func cancelCollapseTask() {
        collapseTask?.cancel()
        collapseTask = nil
        isCollapsePending = false
    }
}
