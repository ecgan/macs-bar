import Foundation

enum AppSettings {
    static let autoHideEnabledKey = "autoHideEnabled"
    static let autoHideActivationHeightKey = "autoHideActivationHeight"
    static let showInFrontOfDockKey = "showInFrontOfDock"
    static let barPlacementAreaKey = "barPlacementArea"
    static let defaultAutoHideActivationHeight = 8.0
    static let autoHideActivationHeightRange = 2.0...20.0
    static let defaultShowInFrontOfDock = false
    static let defaultBarPlacementArea = BarPlacementArea.visibleFrame

    static func showInFrontOfDock(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: showInFrontOfDockKey) as? Bool
            ?? defaultShowInFrontOfDock
    }

    static func barPlacementArea(defaults: UserDefaults = .standard) -> BarPlacementArea {
        guard let rawValue = defaults.string(forKey: barPlacementAreaKey),
              let area = BarPlacementArea(rawValue: rawValue) else {
            return defaultBarPlacementArea
        }
        return area
    }
}
