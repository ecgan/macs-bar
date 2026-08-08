enum PanelVisibilityPolicy {
    static func shouldShowPanel(
        isShowDesktopActive: Bool,
        isFullscreenActive: Bool
    ) -> Bool {
        !isShowDesktopActive && !isFullscreenActive
    }
}
