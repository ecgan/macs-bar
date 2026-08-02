import Foundation

enum AppSettings {
    static let autoHideEnabledKey = "autoHideEnabled"
    static let autoHideActivationHeightKey = "autoHideActivationHeight"
    static let panelLevelKey = "panelLevel"
    static let barPlacementAreaKey = "barPlacementArea"
    static let defaultAutoHideActivationHeight = 8.0
    static let autoHideActivationHeightRange = 2.0...20.0
    static let defaultPanelLevel = PanelLevel.behindDock
    static let defaultBarPlacementArea = BarPlacementArea.visibleFrame

    static func panelLevel(defaults: UserDefaults = .standard) -> PanelLevel {
        guard let rawValue = defaults.string(forKey: panelLevelKey),
              let level = PanelLevel(rawValue: rawValue) else {
            return defaultPanelLevel
        }
        return level
    }

    static func barPlacementArea(defaults: UserDefaults = .standard) -> BarPlacementArea {
        guard let rawValue = defaults.string(forKey: barPlacementAreaKey),
              let area = BarPlacementArea(rawValue: rawValue) else {
            return defaultBarPlacementArea
        }
        return area
    }
}
