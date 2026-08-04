import Foundation
import Testing
@testable import MacsBar

@Suite("Welcome Guide State Tests")
struct WelcomeGuideStateTests {
    @Test("A new installation presents the guide")
    func newInstallationPresentsGuide() {
        let defaults = makeDefaults()
        let state = WelcomeGuideState(defaults: defaults)

        #expect(state.shouldPresentAutomatically(accessibilityGranted: false))
        #expect(state.completedVersion == 0)
    }

    @Test("Completing the guide prevents it from appearing again")
    func completedGuideDoesNotReappear() {
        let defaults = makeDefaults()
        let state = WelcomeGuideState(defaults: defaults)

        state.markCompleted()

        #expect(!state.shouldPresentAutomatically(accessibilityGranted: false))
        #expect(state.completedVersion == WelcomeGuideState.currentVersion)
    }

    @Test("Accessibility access identifies an existing installation")
    func accessibilityMigratesExistingInstallation() {
        let defaults = makeDefaults()
        let state = WelcomeGuideState(defaults: defaults)

        #expect(!state.shouldPresentAutomatically(accessibilityGranted: true))
        #expect(state.completedVersion == WelcomeGuideState.currentVersion)
    }

    @Test("A saved app preference identifies an existing installation")
    func savedPreferenceMigratesExistingInstallation() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: AppSettings.autoHideEnabledKey)
        let state = WelcomeGuideState(defaults: defaults)

        #expect(!state.shouldPresentAutomatically(accessibilityGranted: false))
        #expect(state.completedVersion == WelcomeGuideState.currentVersion)
    }

    @Test("A newer guide version appears after an older version was completed")
    func newerGuideVersionAppears() {
        let defaults = makeDefaults()
        defaults.set(1, forKey: WelcomeGuideState.completedVersionKey)
        let state = WelcomeGuideState(defaults: defaults, currentVersion: 2)

        #expect(state.shouldPresentAutomatically(accessibilityGranted: true))
        #expect(state.completedVersion == 1)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "welcome-guide-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
