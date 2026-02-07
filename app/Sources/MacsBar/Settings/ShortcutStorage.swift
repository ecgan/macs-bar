import Foundation
import AppKit
import Carbon.HIToolbox

enum ShortcutAction: String, CaseIterable {
    case previousWindow
    case nextWindow

    var displayName: String {
        switch self {
        case .previousWindow: return "Switch to Previous Window"
        case .nextWindow: return "Switch to Next Window"
        }
    }

    var defaultKeyCode: Int {
        switch self {
        case .previousWindow: return kVK_LeftArrow  // 123
        case .nextWindow: return kVK_RightArrow     // 124
        }
    }

    var defaultModifiers: NSEvent.ModifierFlags {
        [.control, .option]
    }
}

struct KeyboardShortcut: Codable, Equatable {
    let keyCode: Int
    let modifiers: NSEvent.ModifierFlags

    init(keyCode: Int, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    enum CodingKeys: String, CodingKey {
        case keyCode
        case modifierRawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(Int.self, forKey: .keyCode)
        let rawValue = try container.decode(UInt.self, forKey: .modifierRawValue)
        modifiers = NSEvent.ModifierFlags(rawValue: rawValue)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers.rawValue, forKey: .modifierRawValue)
    }
}

@MainActor
class ShortcutStorage: ObservableObject {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private static let shortcutsKey = "keyboardShortcuts"

    @Published private(set) var shortcuts: [ShortcutAction: KeyboardShortcut] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadShortcuts()
    }

    func shortcut(for action: ShortcutAction) -> KeyboardShortcut {
        shortcuts[action] ?? KeyboardShortcut(
            keyCode: action.defaultKeyCode,
            modifiers: action.defaultModifiers
        )
    }

    func setShortcut(_ shortcut: KeyboardShortcut, for action: ShortcutAction) {
        shortcuts[action] = shortcut
        saveShortcuts()
    }

    func resetToDefaults() {
        shortcuts.removeAll()
        defaults.removeObject(forKey: Self.shortcutsKey)
    }

    private func loadShortcuts() {
        guard let data = defaults.data(forKey: Self.shortcutsKey),
              let decoded = try? decoder.decode([String: KeyboardShortcut].self, from: data) else {
            return
        }
        for (key, value) in decoded {
            if let action = ShortcutAction(rawValue: key) {
                shortcuts[action] = value
            }
        }
    }

    private func saveShortcuts() {
        let toEncode = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
        if let data = try? encoder.encode(toEncode) {
            defaults.set(data, forKey: Self.shortcutsKey)
        }
    }
}
