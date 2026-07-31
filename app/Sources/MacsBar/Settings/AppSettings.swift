import Foundation

enum AppSettings {
    static let autoHideEnabledKey = "autoHideEnabled"
    static let autoHideActivationHeightKey = "autoHideActivationHeight"
    static let showInFrontOfDockKey = "showInFrontOfDock"
    static let defaultAutoHideActivationHeight = 8.0
    static let autoHideActivationHeightRange = 2.0...20.0
    static let defaultShowInFrontOfDock = true

    static func showInFrontOfDock(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: showInFrontOfDockKey) as? Bool
            ?? defaultShowInFrontOfDock
    }
}
