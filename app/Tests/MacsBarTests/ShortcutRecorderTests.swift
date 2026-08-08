import AppKit
import Carbon.HIToolbox
import Testing
@testable import MacsBar

@Suite("Shortcut Recorder Tests")
struct ShortcutRecorderTests {
    @MainActor
    @Test("Stopping recording resigns first responder")
    func stoppingRecordingResignsFirstResponder() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let recorder = ShortcutRecorderNSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView?.addSubview(recorder)

        recorder.setRecording(true)
        #expect(window.firstResponder === recorder)

        recorder.setRecording(false)
        #expect(window.firstResponder !== recorder)
    }

    @MainActor
    @Test("Stopped recorder ignores key events")
    func stoppedRecorderIgnoresKeyEvents() throws {
        let recorder = ShortcutRecorderNSView()
        var recordedShortcut: KeyboardShortcut?
        recorder.onShortcutRecorded = { keyCode, modifiers in
            recordedShortcut = KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
        }
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "h",
            charactersIgnoringModifiers: "h",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_H)
        ))

        recorder.setRecording(false)
        recorder.keyDown(with: event)

        #expect(recordedShortcut == nil)
    }
}
