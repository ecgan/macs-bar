import SwiftUI
import AppKit

class MacsBarHostingView: NSHostingView<AnyView> {
    var state: SpaceBarState?

    @MainActor required init(rootView: AnyView) {
        super.init(rootView: rootView)
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = self.convert(point, from: self.superview)
        
        guard let state = state else {
            return super.hitTest(point)
        }
        
        let pillWidth = state.pillWidth
        guard pillWidth > 0 else {
            return super.hitTest(point)
        }
        
        let startX = (self.bounds.width - pillWidth) / 2
        let endX = startX + pillWidth
        
        let pillHeight: CGFloat = 32
        let startY = (self.bounds.height - pillHeight) / 2
        let endY = startY + pillHeight
        
        if localPoint.x >= startX && localPoint.x <= endX &&
           localPoint.y >= startY && localPoint.y <= endY {
            return super.hitTest(point)
        }
        
        return nil
    }
}
