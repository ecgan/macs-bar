import Testing
import Foundation
@testable import MacsBar

@Suite("Shortcut Storage Tests")
struct ShortcutStorageTests {
    @Test("Default shortcuts include window navigation and auto-hide toggle")
    @MainActor
    func defaultShortcuts() {
        let defaults = UserDefaults(suiteName: "test-defaults-\(UUID())")!
        let storage = ShortcutStorage(defaults: defaults)

        let prevShortcut = storage.shortcut(for: .previousWindow)
        #expect(prevShortcut.keyCode == 123) // Left arrow
        #expect(prevShortcut.modifiers.contains(.control))
        #expect(prevShortcut.modifiers.contains(.option))

        let nextShortcut = storage.shortcut(for: .nextWindow)
        #expect(nextShortcut.keyCode == 124) // Right arrow
        #expect(nextShortcut.modifiers.contains(.control))
        #expect(nextShortcut.modifiers.contains(.option))

        let toggleAutoHideShortcut = storage.shortcut(for: .toggleAutoHide)
        #expect(toggleAutoHideShortcut.keyCode == 4) // H
        #expect(toggleAutoHideShortcut.modifiers.contains(.control))
        #expect(toggleAutoHideShortcut.modifiers.contains(.option))
    }

    @Test("Can save and load custom shortcuts")
    @MainActor
    func saveAndLoadShortcuts() {
        let defaults = UserDefaults(suiteName: "test-defaults-\(UUID())")!
        let storage = ShortcutStorage(defaults: defaults)

        let customShortcut = KeyboardShortcut(keyCode: 0, modifiers: [.command, .shift]) // Cmd+Shift+A
        storage.setShortcut(customShortcut, for: .toggleAutoHide)

        let loaded = storage.shortcut(for: .toggleAutoHide)
        #expect(loaded.keyCode == 0)
        #expect(loaded.modifiers.contains(.command))
        #expect(loaded.modifiers.contains(.shift))
    }

    @Test("Default shortcuts do not conflict")
    @MainActor
    func defaultShortcutsDoNotConflict() {
        let defaults = UserDefaults(suiteName: "test-defaults-\(UUID())")!
        let storage = ShortcutStorage(defaults: defaults)
        let shortcutIdentifiers = ShortcutAction.allCases.map { action in
            let shortcut = storage.shortcut(for: action)
            return "\(shortcut.keyCode)-\(shortcut.modifiers.rawValue)"
        }

        #expect(Set(shortcutIdentifiers).count == ShortcutAction.allCases.count)
    }

    @Test("Navigation modifier matching is exact")
    func navigationModifierMatchingIsExact() {
        #expect(KeyboardShortcutMatcher.navigationModifiersExactlyMatch(
            [.control, .option],
            overrides: [:]
        ))
        #expect(!KeyboardShortcutMatcher.navigationModifiersExactlyMatch(
            [.control, .option, .shift],
            overrides: [:]
        ))
        #expect(!KeyboardShortcutMatcher.navigationModifiersExactlyMatch(
            [.control],
            overrides: [:]
        ))
    }

    @Test("Only configured navigation modifiers reveal the bar")
    func onlyNavigationModifiersRevealBar() {
        let overrides: [ShortcutAction: KeyboardShortcut] = [
            .previousWindow: KeyboardShortcut(keyCode: 0, modifiers: [.command, .shift]),
            .nextWindow: KeyboardShortcut(keyCode: 1, modifiers: [.command, .option]),
        ]

        #expect(KeyboardShortcutMatcher.navigationModifiersExactlyMatch(
            [.command, .shift],
            overrides: overrides
        ))
        #expect(KeyboardShortcutMatcher.navigationModifiersExactlyMatch(
            [.command, .option],
            overrides: overrides
        ))
        #expect(!KeyboardShortcutMatcher.navigationModifiersExactlyMatch(
            [.control, .option],
            overrides: overrides
        ))
    }

    @Test("Reset restores defaults")
    @MainActor
    func resetToDefaults() {
        let defaults = UserDefaults(suiteName: "test-defaults-\(UUID())")!
        let storage = ShortcutStorage(defaults: defaults)

        let customShortcut = KeyboardShortcut(keyCode: 0, modifiers: [.command])
        storage.setShortcut(customShortcut, for: .previousWindow)

        storage.resetToDefaults()

        let shortcut = storage.shortcut(for: .previousWindow)
        #expect(shortcut.keyCode == 123)
    }

    @Test("setShortcut updates shortcuts dictionary immediately")
    @MainActor
    func setShortcutUpdatesImmediately() {
        let defaults = UserDefaults(suiteName: "test-defaults-\(UUID())")!
        let storage = ShortcutStorage(defaults: defaults)

        // Verify shortcuts dictionary is empty initially (defaults not stored)
        #expect(storage.shortcuts[.previousWindow] == nil)

        // Set a custom shortcut
        let customShortcut = KeyboardShortcut(keyCode: 0, modifiers: [.command, .shift])
        storage.setShortcut(customShortcut, for: .previousWindow)

        // Verify shortcuts dictionary is updated synchronously (no async delay)
        // This is critical - the KeyboardShortcutHandler reads this dictionary on every keypress
        let stored = storage.shortcuts[.previousWindow]
        #expect(stored != nil, "shortcuts dictionary should be updated immediately")
        #expect(stored?.keyCode == 0)
        #expect(stored?.modifiers == [.command, .shift])
    }
}
