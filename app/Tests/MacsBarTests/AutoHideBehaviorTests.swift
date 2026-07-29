import CoreGraphics
import Testing
@testable import MacsBar

@Suite("Auto Hide Behavior Tests")
struct AutoHideBehaviorTests {
    private let screenFrame = CGRect(x: -1440, y: 120, width: 1440, height: 900)

    @Test("Hidden bar reveals along the entire bottom edge")
    func hiddenBarRevealsAtBottomEdge() {
        #expect(AutoHidePolicy.shouldShowBar(
            mouseLocation: CGPoint(x: -1400, y: 121),
            screenFrame: screenFrame,
            barHeight: 36,
            isBarShown: false
        ))

        #expect(AutoHidePolicy.shouldShowBar(
            mouseLocation: CGPoint(x: -20, y: 122),
            screenFrame: screenFrame,
            barHeight: 36,
            isBarShown: false
        ))
    }

    @Test("Hidden bar remains hidden above the activation zone")
    func hiddenBarStaysHiddenAwayFromEdge() {
        #expect(!AutoHidePolicy.shouldShowBar(
            mouseLocation: CGPoint(x: -720, y: 123),
            screenFrame: screenFrame,
            barHeight: 36,
            isBarShown: false
        ))
    }

    @Test("Shown bar remains visible while pointer is inside bar area")
    func shownBarStaysVisibleUnderPointer() {
        #expect(AutoHidePolicy.shouldShowBar(
            mouseLocation: CGPoint(x: -720, y: 155),
            screenFrame: screenFrame,
            barHeight: 36,
            isBarShown: true
        ))

        #expect(!AutoHidePolicy.shouldShowBar(
            mouseLocation: CGPoint(x: -720, y: 157),
            screenFrame: screenFrame,
            barHeight: 36,
            isBarShown: true
        ))
    }

    @Test("Pointer on another display does not reveal bar")
    func pointerOnAnotherDisplayDoesNotRevealBar() {
        #expect(!AutoHidePolicy.shouldShowBar(
            mouseLocation: CGPoint(x: 100, y: 121),
            screenFrame: screenFrame,
            barHeight: 36,
            isBarShown: false
        ))
    }
}
