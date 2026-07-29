import AppKit
import SwiftUI

class MacsBarHostingView: NSHostingView<AnyView> {
    var state: SpaceBarState?

    @MainActor required init(rootView: AnyView) {
        super.init(rootView: rootView)
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let state else { return nil }
        let localPoint = convert(point, from: superview)

        let interactiveFrame: CGRect?
        switch state.presentation {
        case .hidden:
            interactiveFrame = nil
        case .expanded:
            interactiveFrame = BarMetrics.expandedPillFrame(
                in: bounds,
                pillWidth: state.pillWidth
            )
        case .collapsed:
            interactiveFrame = BarMetrics.revealHandleHitFrame(
                in: bounds,
                isFlipped: isFlipped
            )
        }

        guard let interactiveFrame, interactiveFrame.contains(localPoint) else { return nil }
        return super.hitTest(point)
    }
}
