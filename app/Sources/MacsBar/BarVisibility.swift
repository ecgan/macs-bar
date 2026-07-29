import CoreGraphics
import Foundation

enum BarVisibilityMode: String, CaseIterable, Identifiable {
    case overlapAware
    case alwaysVisible

    static let defaultsKey = "barVisibilityMode"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .overlapAware:
            return "Overlap-aware auto-hide"
        case .alwaysVisible:
            return "Always visible"
        }
    }

    static func current(defaults: UserDefaults = .standard) -> BarVisibilityMode {
        guard let rawValue = defaults.string(forKey: defaultsKey),
              let mode = BarVisibilityMode(rawValue: rawValue) else {
            return .overlapAware
        }
        return mode
    }
}

enum BarPresentation: Equatable {
    case hidden
    case expanded
    case collapsed
}

enum BarHoverTarget: Hashable {
    case pill
    case revealHandle
}

enum BarMetrics {
    static let panelHeight: CGFloat = 36
    static let pillHeight: CGFloat = 32
    static let revealHandleWidth: CGFloat = 44
    static let revealHandleHeight: CGFloat = 4
    static let revealHandleHitWidth: CGFloat = 64
    static let revealHandleHitHeight: CGFloat = 10

    static func expandedPillFrame(in bounds: CGRect, pillWidth: CGFloat) -> CGRect? {
        guard pillWidth > 0 else { return nil }
        return CGRect(
            x: bounds.midX - pillWidth / 2,
            y: bounds.midY - pillHeight / 2,
            width: pillWidth,
            height: pillHeight
        )
    }

    static func revealHandleHitFrame(in bounds: CGRect, isFlipped: Bool) -> CGRect {
        CGRect(
            x: bounds.midX - revealHandleHitWidth / 2,
            y: isFlipped ? bounds.maxY - revealHandleHitHeight : bounds.minY,
            width: revealHandleHitWidth,
            height: revealHandleHitHeight
        )
    }
}

enum BarGeometry {
    static func canonicalExpandedPillFrame(
        screenFrame: CGRect,
        pillWidth: CGFloat
    ) -> CGRect? {
        guard pillWidth > 0, !screenFrame.isEmpty else { return nil }
        let verticalInset = (BarMetrics.panelHeight - BarMetrics.pillHeight) / 2
        return CGRect(
            x: screenFrame.midX - pillWidth / 2,
            y: screenFrame.maxY - verticalInset - BarMetrics.pillHeight,
            width: pillWidth,
            height: BarMetrics.pillHeight
        )
    }

    static func window(
        _ windowFrame: CGRect,
        overlapsCanonicalPillOn screenFrame: CGRect,
        pillWidth: CGFloat,
        tolerance: CGFloat = 1
    ) -> Bool {
        guard let pillFrame = canonicalExpandedPillFrame(
            screenFrame: screenFrame,
            pillWidth: pillWidth
        ) else {
            return false
        }
        return pillFrame.insetBy(dx: -tolerance, dy: -tolerance).intersects(windowFrame)
    }
}

enum BarVisibilityPolicy {
    static func presentation(
        mode: BarVisibilityMode,
        isFullscreenSuppressed: Bool,
        hasWindows: Bool,
        focusedWindowOverlapsPill: Bool,
        isPointerInside: Bool
    ) -> BarPresentation {
        guard hasWindows, !isFullscreenSuppressed else { return .hidden }
        guard mode == .overlapAware else { return .expanded }
        guard focusedWindowOverlapsPill else { return .expanded }
        return isPointerInside ? .expanded : .collapsed
    }
}
