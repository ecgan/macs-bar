import Foundation

struct WelcomeGuideState {
    static let currentVersion = 1
    static let completedVersionKey = "completedWelcomeGuideVersion"

    private static let existingPreferenceKeys = [
        AppSettings.autoHideEnabledKey,
        AppSettings.autoHideActivationHeightKey,
        AppSettings.panelLevelKey,
        AppSettings.barPlacementAreaKey,
        "keyboardShortcuts",
        "launchAtLogin",
    ]

    private let defaults: UserDefaults
    private let currentVersion: Int

    init(
        defaults: UserDefaults = .standard,
        currentVersion: Int = Self.currentVersion
    ) {
        self.defaults = defaults
        self.currentVersion = currentVersion
    }

    var completedVersion: Int {
        defaults.integer(forKey: Self.completedVersionKey)
    }

    func shouldPresentAutomatically(accessibilityGranted: Bool) -> Bool {
        if completedVersion > 0 {
            return completedVersion < currentVersion
        }

        // The first release with a welcome guide should not interrupt people who
        // were already using Macs Bar. Accessibility access or a saved setting is
        // evidence of an existing installation.
        if accessibilityGranted || Self.existingPreferenceKeys.contains(where: {
            defaults.object(forKey: $0) != nil
        }) {
            markCompleted()
            return false
        }

        return true
    }

    func markCompleted() {
        defaults.set(currentVersion, forKey: Self.completedVersionKey)
    }
}
