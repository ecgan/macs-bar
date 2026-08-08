import CoreGraphics
import Testing
@testable import MacsBar

@Suite("Show Desktop Initial State Policy Tests")
struct ShowDesktopInitialStatePolicyTests {
    private let dockWindowLevel = CGWindowLevelForKey(.dockWindow)

    @Test("Normal desktop is inactive")
    func normalDesktop() {
        #expect(!ShowDesktopInitialStatePolicy.isShowDesktopActive(
            dockWindowLayers: [dockWindowLevel]
        ))
    }

    @Test("Show Desktop backdrop is active")
    func showDesktop() {
        #expect(ShowDesktopInitialStatePolicy.isShowDesktopActive(
            dockWindowLayers: [
                dockWindowLevel,
                dockWindowLevel - 2,
            ]
        ))
    }

    @Test("Multiple displays may contribute Show Desktop backdrops")
    func showDesktopWithMultipleDisplays() {
        #expect(ShowDesktopInitialStatePolicy.isShowDesktopActive(
            dockWindowLayers: [
                dockWindowLevel,
                dockWindowLevel - 2,
                dockWindowLevel - 2,
            ]
        ))
    }

    @Test("Mission Control is not Show Desktop")
    func missionControl() {
        #expect(!ShowDesktopInitialStatePolicy.isShowDesktopActive(
            dockWindowLayers: [
                dockWindowLevel,
                dockWindowLevel,
                dockWindowLevel - 2,
            ]
        ))
    }
}
