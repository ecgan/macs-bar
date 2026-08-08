import CoreGraphics

enum ShowDesktopInitialStatePolicy {
    static func isShowDesktopActive(
        dockWindowLayers: [CGWindowLevel]
    ) -> Bool {
        let dockWindowLevel = CGWindowLevelForKey(.dockWindow)
        let exposeBackdropLevel = dockWindowLevel - 2

        let hasExposeBackdrop = dockWindowLayers.contains(exposeBackdropLevel)
        let dockLevelWindowCount = dockWindowLayers.count {
            $0 == dockWindowLevel
        }

        // Show Desktop adds the Exposé backdrop while retaining only the Dock's
        // base window. Mission Control and App Exposé add another Dock-level window.
        return hasExposeBackdrop && dockLevelWindowCount == 1
    }
}
