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
