import AppKit
import CoreGraphics

enum PanelLevel: String {
    case behindDock
    case inFrontOfDock
}

enum PanelLevelPolicy {
    static func windowLevel(for panelLevel: PanelLevel) -> NSWindow.Level {
        switch panelLevel {
        case .behindDock:
            return .floating
        case .inFrontOfDock:
            let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
            return NSWindow.Level(rawValue: dockLevel + 1)
        }
    }
}
