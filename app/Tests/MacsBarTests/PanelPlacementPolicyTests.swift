import AppKit
import Foundation
import Testing
@testable import MacsBar

@Suite("Panel Placement Policy Tests")
struct PanelPlacementPolicyTests {
    private let bottomDockGeometry = PanelScreenGeometry(
        screenFrame: NSRect(x: -1440, y: 100, width: 1440, height: 900),
        visibleFrame: NSRect(x: -1440, y: 160, width: 1440, height: 816)
    )

    @Test("Screen frame placement uses the entire display")
    func screenFramePlacement() {
        let frame = PanelPlacementPolicy.barFrame(
            for: bottomDockGeometry,
            area: .screenFrame,
            barHeight: 36
        )

        #expect(frame == NSRect(x: -1440, y: 100, width: 1440, height: 36))
    }

    @Test("Visible frame placement sits above a bottom Dock")
    func visibleFramePlacementAboveBottomDock() {
        let frame = PanelPlacementPolicy.barFrame(
            for: bottomDockGeometry,
            area: .visibleFrame,
            barHeight: 36
        )

        #expect(frame == NSRect(x: -1440, y: 160, width: 1440, height: 36))
    }

    @Test("Visible frame placement avoids a side Dock")
    func visibleFramePlacementBesideSideDock() {
        let geometry = PanelScreenGeometry(
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: NSRect(x: 80, y: 0, width: 1432, height: 954)
        )

        let frame = PanelPlacementPolicy.barFrame(
            for: geometry,
            area: .visibleFrame,
            barHeight: 36
        )

        #expect(frame == NSRect(x: 80, y: 0, width: 1432, height: 36))
    }

    @Test("Placement defaults to screen frame and respects a saved choice")
    func placementPreference() {
        let defaults = UserDefaults(suiteName: "test-defaults-\(UUID())")!

        #expect(AppSettings.barPlacementArea(defaults: defaults) == .screenFrame)

        defaults.set(
            BarPlacementArea.visibleFrame.rawValue,
            forKey: AppSettings.barPlacementAreaKey
        )
        #expect(AppSettings.barPlacementArea(defaults: defaults) == .visibleFrame)
    }

    @Test("Invalid placement preference falls back to screen frame")
    func invalidPlacementPreference() {
        let defaults = UserDefaults(suiteName: "test-defaults-\(UUID())")!
        defaults.set("invalid", forKey: AppSettings.barPlacementAreaKey)

        #expect(AppSettings.barPlacementArea(defaults: defaults) == .screenFrame)
    }
}
