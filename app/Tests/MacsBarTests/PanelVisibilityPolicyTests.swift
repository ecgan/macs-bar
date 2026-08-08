import Testing
@testable import MacsBar

@Suite("Panel Visibility Policy Tests")
struct PanelVisibilityPolicyTests {
    @Test("Mission Control notification names map to expected states")
    func missionControlNotificationNames() {
        #expect(MissionControlState(rawValue: "AXExposeShowDesktop") == .showDesktop)
        #expect(MissionControlState(rawValue: "AXExposeExit") == .inactive)
    }

    @Test("Panel is visible during normal desktop use")
    func normalDesktop() {
        #expect(PanelVisibilityPolicy.shouldShowPanel(
            isShowDesktopActive: false,
            isFullscreenActive: false
        ))
    }

    @Test("Panel is hidden while Show Desktop is active")
    func showDesktop() {
        #expect(!PanelVisibilityPolicy.shouldShowPanel(
            isShowDesktopActive: true,
            isFullscreenActive: false
        ))
    }

    @Test("Panel remains hidden in fullscreen after Show Desktop exits")
    func fullscreenAfterShowDesktop() {
        #expect(!PanelVisibilityPolicy.shouldShowPanel(
            isShowDesktopActive: false,
            isFullscreenActive: true
        ))
    }
}
