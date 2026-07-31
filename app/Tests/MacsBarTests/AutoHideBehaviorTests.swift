import CoreGraphics
import Testing
@testable import MacsBar

@Suite("Auto Hide Behavior Tests")
struct AutoHideBehaviorTests {
    private let screenFrame = CGRect(x: -1440, y: 120, width: 1440, height: 900)
    private let activationHeight: CGFloat = 8

    @Test("Hidden bar reveals along the entire bottom edge")
    func hiddenBarRevealsAtBottomEdge() {
        #expect(AutoHidePolicy.shouldShowBar(
            mouseLocation: CGPoint(x: -1400, y: 121),
            screenFrame: screenFrame,
            barHeight: 36,
            activationHeight: activationHeight,
            isBarShown: false
        ))

        #expect(AutoHidePolicy.shouldShowBar(
            mouseLocation: CGPoint(x: -20, y: 128),
            screenFrame: screenFrame,
            barHeight: 36,
            activationHeight: activationHeight,
            isBarShown: false
        ))
    }

    @Test("Hidden bar remains hidden above the activation zone")
    func hiddenBarStaysHiddenAwayFromEdge() {
        #expect(!AutoHidePolicy.shouldShowBar(
            mouseLocation: CGPoint(x: -720, y: 129),
            screenFrame: screenFrame,
            barHeight: 36,
            activationHeight: activationHeight,
            isBarShown: false
        ))
    }

    @Test("Shown bar remains visible while pointer is inside bar area")
    func shownBarStaysVisibleUnderPointer() {
        #expect(AutoHidePolicy.shouldShowBar(
            mouseLocation: CGPoint(x: -720, y: 155),
            screenFrame: screenFrame,
            barHeight: 36,
            activationHeight: activationHeight,
            isBarShown: true
        ))

        #expect(!AutoHidePolicy.shouldShowBar(
            mouseLocation: CGPoint(x: -720, y: 157),
            screenFrame: screenFrame,
            barHeight: 36,
            activationHeight: activationHeight,
            isBarShown: true
        ))
    }

    @Test("Pointer on another display does not reveal bar")
    func pointerOnAnotherDisplayDoesNotRevealBar() {
        #expect(!AutoHidePolicy.shouldShowBar(
            mouseLocation: CGPoint(x: 100, y: 121),
            screenFrame: screenFrame,
            barHeight: 36,
            activationHeight: activationHeight,
            isBarShown: false
        ))
    }

    @Test("Larger activation area reveals bar farther from edge")
    func customizableActivationArea() {
        let mouseLocation = CGPoint(x: -720, y: 132)

        #expect(!AutoHidePolicy.shouldShowBar(
            mouseLocation: mouseLocation,
            screenFrame: screenFrame,
            barHeight: 36,
            activationHeight: 8,
            isBarShown: false
        ))

        #expect(AutoHidePolicy.shouldShowBar(
            mouseLocation: mouseLocation,
            screenFrame: screenFrame,
            barHeight: 36,
            activationHeight: 16,
            isBarShown: false
        ))
    }
}
