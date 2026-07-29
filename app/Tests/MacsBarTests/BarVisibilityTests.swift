import CoreGraphics
import MacWindowTracker
import Testing
@testable import MacsBar

@Suite("Bar Visibility Tests")
struct BarVisibilityTests {
    private let screenFrame = CGRect(x: 0, y: 0, width: 1_000, height: 800)

    @Test("Canonical pill frame is centered at the physical bottom of its screen")
    func canonicalPillFrame() {
        let frame = BarGeometry.canonicalExpandedPillFrame(
            screenFrame: screenFrame,
            pillWidth: 200
        )

        #expect(frame == CGRect(x: 400, y: 766, width: 200, height: 32))
    }

    @Test("Only windows behind the centered pill count as overlapping")
    func overlapUsesPillInsteadOfFullPanel() {
        let bottomLeftWindow = CGRect(x: 0, y: 700, width: 300, height: 100)
        let bottomCenterWindow = CGRect(x: 450, y: 700, width: 100, height: 100)

        #expect(!BarGeometry.window(
            bottomLeftWindow,
            overlapsCanonicalPillOn: screenFrame,
            pillWidth: 200
        ))
        #expect(BarGeometry.window(
            bottomCenterWindow,
            overlapsCanonicalPillOn: screenFrame,
            pillWidth: 200
        ))
    }

    @Test("Fullscreen and empty states take precedence")
    func hiddenStatePrecedence() {
        #expect(BarVisibilityPolicy.presentation(
            mode: .alwaysVisible,
            isFullscreenSuppressed: true,
            hasWindows: true,
            focusedWindowOverlapsPill: false,
            isPointerInside: false
        ) == .hidden)
        #expect(BarVisibilityPolicy.presentation(
            mode: .alwaysVisible,
            isFullscreenSuppressed: false,
            hasWindows: false,
            focusedWindowOverlapsPill: false,
            isPointerInside: false
        ) == .hidden)
    }

    @Test("Overlap-aware mode collapses only for an unhovered overlap")
    func overlapAwarePolicy() {
        #expect(BarVisibilityPolicy.presentation(
            mode: .overlapAware,
            isFullscreenSuppressed: false,
            hasWindows: true,
            focusedWindowOverlapsPill: true,
            isPointerInside: false
        ) == .collapsed)
        #expect(BarVisibilityPolicy.presentation(
            mode: .overlapAware,
            isFullscreenSuppressed: false,
            hasWindows: true,
            focusedWindowOverlapsPill: true,
            isPointerInside: true
        ) == .expanded)
        #expect(BarVisibilityPolicy.presentation(
            mode: .overlapAware,
            isFullscreenSuppressed: false,
            hasWindows: true,
            focusedWindowOverlapsPill: false,
            isPointerInside: false
        ) == .expanded)
    }

    @Test("Always-visible mode ignores overlap")
    func alwaysVisiblePolicy() {
        #expect(BarVisibilityPolicy.presentation(
            mode: .alwaysVisible,
            isFullscreenSuppressed: false,
            hasWindows: true,
            focusedWindowOverlapsPill: true,
            isPointerInside: false
        ) == .expanded)
    }

    @Test("Hover reveal waits before collapsing again")
    @MainActor
    func delayedCollapseAfterHover() async {
        let state = makeState()
        state.updatePillWidth(200)
        state.updateContext(
            windows: [makeWindow(frame: CGRect(x: 350, y: 700, width: 300, height: 100))],
            screenFrame: screenFrame,
            focusedWindowFrame: CGRect(x: 350, y: 700, width: 300, height: 100),
            visibilityMode: .overlapAware,
            isFullscreenSuppressed: false
        )
        #expect(state.presentation == .collapsed)

        state.setHovering(true, target: .revealHandle)
        #expect(state.presentation == .expanded)

        state.setHovering(false, target: .revealHandle)
        #expect(state.presentation == .expanded)

        try? await Task.sleep(for: .milliseconds(600))
        #expect(state.presentation == .collapsed)
    }

    @Test("Transient focus loss preserves state before expanding")
    @MainActor
    func focusLossGracePeriod() async {
        let state = makeState()
        let window = makeWindow(frame: CGRect(x: 350, y: 700, width: 300, height: 100))
        state.updatePillWidth(200)
        state.updateContext(
            windows: [window],
            screenFrame: screenFrame,
            focusedWindowFrame: window.frame,
            visibilityMode: .overlapAware,
            isFullscreenSuppressed: false
        )
        #expect(state.presentation == .collapsed)

        state.updateContext(
            windows: [window],
            screenFrame: screenFrame,
            focusedWindowFrame: nil,
            visibilityMode: .overlapAware,
            isFullscreenSuppressed: false
        )
        #expect(state.presentation == .collapsed)

        try? await Task.sleep(for: .milliseconds(300))
        #expect(state.presentation == .expanded)
    }

    @MainActor
    private func makeState() -> SpaceBarState {
        SpaceBarState(
            spaceId: 1,
            onActivate: { _ in },
            onClose: { _ in }
        )
    }

    private func makeWindow(frame: CGRect) -> TrackedWindow {
        TrackedWindow(
            id: 1,
            title: "Test Window",
            appName: "Test App",
            appBundleId: "com.example.test",
            appPid: 1,
            frame: frame,
            monitorId: 1,
            isFocused: true
        )
    }
}
