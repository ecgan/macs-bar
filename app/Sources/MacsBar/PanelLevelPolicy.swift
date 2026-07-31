import AppKit
import CoreGraphics

enum PanelLevelPolicy {
    static func windowLevel(showInFrontOfDock: Bool) -> NSWindow.Level {
        guard showInFrontOfDock else { return .floating }

        let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
        return NSWindow.Level(rawValue: dockLevel + 1)
    }
}
