import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import MacsBar

@Suite("Panel Level Policy Tests")
struct PanelLevelPolicyTests {
    @Test("Behind Dock uses the floating window level")
    func behindDockLevel() {
        let level = PanelLevelPolicy.windowLevel(for: .behindDock)

        #expect(level == .floating)
    }

    @Test("In front of Dock uses the level immediately above the Dock")
    func inFrontOfDockLevel() {
        let level = PanelLevelPolicy.windowLevel(for: .inFrontOfDock)
        let dockLevel = Int(CGWindowLevelForKey(.dockWindow))

        #expect(level.rawValue == dockLevel + 1)
        #expect(level.rawValue < Int(CGWindowLevelForKey(.mainMenuWindow)))
    }

    @Test("Dock layering defaults to behind and respects a saved choice")
    func dockLayeringPreference() {
        let defaults = UserDefaults(suiteName: "test-defaults-\(UUID())")!

        #expect(AppSettings.panelLevel(defaults: defaults) == .behindDock)

        defaults.set(
            PanelLevel.inFrontOfDock.rawValue,
            forKey: AppSettings.panelLevelKey
        )
        #expect(AppSettings.panelLevel(defaults: defaults) == .inFrontOfDock)

        defaults.set(
            PanelLevel.behindDock.rawValue,
            forKey: AppSettings.panelLevelKey
        )
        #expect(AppSettings.panelLevel(defaults: defaults) == .behindDock)
    }

    @Test("Invalid panel level preference falls back to behind Dock")
    func invalidPanelLevelPreference() {
        let defaults = UserDefaults(suiteName: "test-defaults-\(UUID())")!
        defaults.set("invalid", forKey: AppSettings.panelLevelKey)

        #expect(AppSettings.panelLevel(defaults: defaults) == .behindDock)
    }
}
