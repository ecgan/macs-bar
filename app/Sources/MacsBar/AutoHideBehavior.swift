import AppKit
import QuartzCore

enum AutoHidePolicy {
    static let revealDelay: TimeInterval = 0.15
    static let hideDelay: TimeInterval = 0.30
    static let animationDuration: TimeInterval = 0.22

    static func shouldShowBar(
        mouseLocation: CGPoint,
        screenFrame: CGRect,
        barHeight: CGFloat,
        activationHeight: CGFloat,
        isBarShown: Bool
    ) -> Bool {
        let isOnScreen = mouseLocation.x >= screenFrame.minX
            && mouseLocation.x < screenFrame.maxX
            && mouseLocation.y >= screenFrame.minY
            && mouseLocation.y < screenFrame.maxY

        guard isOnScreen else { return false }

        let activeHeight = isBarShown ? barHeight : max(0, activationHeight)
        return mouseLocation.y <= screenFrame.minY + activeHeight
    }
}

@MainActor
final class MacsBarPanel: NSPanel {
    var onContextMenuTrackingChanged: ((Bool) -> Void)?

    override func sendEvent(_ event: NSEvent) {
        let isContextMenuGesture = event.type == .rightMouseDown
            || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))

        guard isContextMenuGesture else {
            super.sendEvent(event)
            return
        }

        onContextMenuTrackingChanged?(true)
        defer { onContextMenuTrackingChanged?(false) }
        super.sendEvent(event)
    }
}

@MainActor
final class MacsBarPanelContentView: NSView {
    private let hostingView: MacsBarHostingView
    private(set) var isBarShown = true
    private var isPanelInteractionEnabled = true

    init(hostingView: MacsBarHostingView, frame frameRect: NSRect) {
        self.hostingView = hostingView
        super.init(frame: frameRect)

        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isBarShown, isPanelInteractionEnabled else { return nil }
        let hostingPoint = hostingView.convert(point, from: self)
        return hostingView.hitTest(hostingPoint)
    }

    func setPanelInteractionEnabled(_ enabled: Bool) {
        isPanelInteractionEnabled = enabled
    }

    func setBarShown(_ shown: Bool, animated: Bool) {
        guard shown != isBarShown else { return }
        isBarShown = shown

        let targetAlpha: CGFloat = shown ? 1 : 0

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = AutoHidePolicy.animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                hostingView.animator().alphaValue = targetAlpha
            }
        } else {
            hostingView.alphaValue = targetAlpha
        }
    }
}
