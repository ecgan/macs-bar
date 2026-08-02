import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import MacsBar

@Suite("Panel Level Policy Tests")
struct PanelLevelPolicyTests {
    @Test("Behind Dock uses the floating window level")
    func behindDockLevel() {
        let level = PanelLevelPolicy.windowLevel(showInFrontOfDock: false)

        #expect(level == .floating)
    }

    @Test("In front of Dock uses the level immediately above the Dock")
    func inFrontOfDockLevel() {
        let level = PanelLevelPolicy.windowLevel(showInFrontOfDock: true)
        let dockLevel = Int(CGWindowLevelForKey(.dockWindow))

        #expect(level.rawValue == dockLevel + 1)
        #expect(level.rawValue < Int(CGWindowLevelForKey(.mainMenuWindow)))
    }

    @Test("Dock layering defaults to behind and respects a saved choice")
    func dockLayeringPreference() {
        let defaults = UserDefaults(suiteName: "test-defaults-\(UUID())")!

        #expect(!AppSettings.showInFrontOfDock(defaults: defaults))

        defaults.set(true, forKey: AppSettings.showInFrontOfDockKey)
        #expect(AppSettings.showInFrontOfDock(defaults: defaults))

        defaults.set(false, forKey: AppSettings.showInFrontOfDockKey)
        #expect(!AppSettings.showInFrontOfDock(defaults: defaults))
    }
}
