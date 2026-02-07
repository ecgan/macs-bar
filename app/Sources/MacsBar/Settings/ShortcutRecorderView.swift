import SwiftUI
import Carbon.HIToolbox

struct ShortcutRecorderView: View {
    let action: ShortcutAction
    @Binding var shortcut: KeyboardShortcut
    @State private var isRecording = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.displayName)
                    .font(.body)
            }

            Spacer()

            Button(action: { isRecording.toggle() }) {
                Text(isRecording ? "Press shortcut..." : shortcutDisplayString)
                    .frame(minWidth: 120)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .background(
                ShortcutRecorderEventHandler(
                    isRecording: $isRecording,
                    shortcut: $shortcut
                )
            )
        }
    }

    private var shortcutDisplayString: String {
        var parts: [String] = []
        if shortcut.modifiers.contains(.control) { parts.append("⌃") }
        if shortcut.modifiers.contains(.option) { parts.append("⌥") }
        if shortcut.modifiers.contains(.shift) { parts.append("⇧") }
        if shortcut.modifiers.contains(.command) { parts.append("⌘") }
        parts.append(keyCodeToString(shortcut.keyCode))
        return parts.joined()
    }

    private func keyCodeToString(_ keyCode: Int) -> String {
        switch keyCode {
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            // Convert keyCode to character
            if let char = keyCodeToCharacter(keyCode) {
                return char.uppercased()
            }
            return "Key \(keyCode)"
        }
    }

    private func keyCodeToCharacter(_ keyCode: Int) -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let dataRef = unsafeBitCast(layoutData, to: CFData.self)
        let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(dataRef), to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length: Int = 0

        let error = UCKeyTranslate(
            keyboardLayout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDown),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &length,
            &chars
        )

        guard error == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}

struct ShortcutRecorderEventHandler: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var shortcut: KeyboardShortcut

    func makeNSView(context: Context) -> NSView {
        let view = ShortcutRecorderNSView()
        view.onShortcutRecorded = { keyCode, modifiers in
            shortcut = KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
            isRecording = false
        }
        view.onCancel = {
            isRecording = false
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ShortcutRecorderNSView else { return }
        if isRecording {
            view.window?.makeFirstResponder(view)
        }
    }
}

class ShortcutRecorderNSView: NSView {
    var onShortcutRecorded: ((Int, NSEvent.ModifierFlags) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == kVK_Escape {
            onCancel?()
            return
        }

        let modifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
        guard !modifiers.isEmpty else {
            // Require at least one modifier
            NSSound.beep()
            return
        }

        onShortcutRecorded?(Int(event.keyCode), modifiers)
    }
}
