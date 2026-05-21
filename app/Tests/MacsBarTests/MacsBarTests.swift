import Testing
import CoreGraphics
@testable import MacsBar

@Suite("Macs Bar Tests")
struct MacsBarTests {
    @Test("Clamp maximized window into the safe frame")
    func clampMaximizedWindowIntoSafeFrame() {
        let monitorFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visibleFrame = CGRect(x: 0, y: 28, width: 1512, height: 954)
        let windowFrame = CGRect(x: 0, y: 28, width: 1512, height: 954)

        let adjusted = MaximizedWindowCascadeAdjuster.adjustedFrame(
            for: windowFrame,
            monitorFrame: monitorFrame,
            visibleFrame: visibleFrame,
            barHeight: 36,
            tolerance: 2
        )

        #expect(adjusted?.origin == CGPoint(x: 0, y: 28))
        #expect(adjusted?.size == CGSize(width: 1512, height: 918))
    }

    @Test("Clamp cascaded window upward when it overlaps the bar")
    func clampCascadedWindowUpward() {
        let monitorFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visibleFrame = CGRect(x: 0, y: 28, width: 1512, height: 954)
        let windowFrame = CGRect(x: 20, y: 48, width: 1492, height: 898)

        let adjusted = MaximizedWindowCascadeAdjuster.adjustedFrame(
            for: windowFrame,
            monitorFrame: monitorFrame,
            visibleFrame: visibleFrame,
            barHeight: 36,
            tolerance: 2
        )

        #expect(adjusted?.origin == CGPoint(x: 0, y: 28))
        #expect(adjusted?.size == CGSize(width: 1512, height: 918))
    }

    @Test("Ignore normal windows that users moved manually")
    func ignoreManuallyMovedWindow() {
        let monitorFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visibleFrame = CGRect(x: 0, y: 28, width: 1512, height: 954)
        let manuallyMovedWindow = CGRect(x: -120, y: 60, width: 1200, height: 800)

        let adjusted = MaximizedWindowCascadeAdjuster.adjustedFrame(
            for: manuallyMovedWindow,
            monitorFrame: monitorFrame,
            visibleFrame: visibleFrame,
            barHeight: 36,
            tolerance: 2
        )

        #expect(adjusted == nil)
    }
}
