import Testing
import Foundation
@testable import MacsBar

@Suite("Shortcut Storage Tests")
struct ShortcutStorageTests {
    @Test("Default shortcuts are Ctrl+Alt+Arrow keys")
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
    }

    @Test("Can save and load custom shortcuts")
    @MainActor
    func saveAndLoadShortcuts() {
        let defaults = UserDefaults(suiteName: "test-defaults-\(UUID())")!
        let storage = ShortcutStorage(defaults: defaults)

        let customShortcut = KeyboardShortcut(keyCode: 0, modifiers: [.command, .shift]) // Cmd+Shift+A
        storage.setShortcut(customShortcut, for: .previousWindow)

        let loaded = storage.shortcut(for: .previousWindow)
        #expect(loaded.keyCode == 0)
        #expect(loaded.modifiers.contains(.command))
        #expect(loaded.modifiers.contains(.shift))
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
}
