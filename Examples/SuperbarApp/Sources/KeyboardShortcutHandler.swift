@preconcurrency import Cocoa
import MacWindowTracker

@MainActor
final class KeyboardShortcutHandler {
    weak var tracker: WindowTracker?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    nonisolated(unsafe) private var tapRef: CFMachPort?
    private var lastActivatedWindowId: CGWindowID?

    func start() {
        let eventMask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, _, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let handler = Unmanaged<KeyboardShortcutHandler>.fromOpaque(userInfo).takeUnretainedValue()
                return handler.handleCGEvent(event)
            },
            userInfo: userInfo
        ) else {
            print("KeyboardShortcutHandler: Failed to create event tap. Ensure Accessibility permission is granted.")
            return
        }

        eventTap = tap
        tapRef = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source

        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source!, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "KeyboardShortcutHandler"
        thread.start()
        tapThread = thread
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopSourceInvalidate(source)
        }
        tapThread?.cancel()
        tapThread = nil
        eventTap = nil
        tapRef = nil
        runLoopSource = nil
    }

    private nonisolated func handleCGEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        guard flags.contains(.maskControl),
              flags.contains(.maskAlternate),
              !flags.contains(.maskCommand),
              !flags.contains(.maskShift) else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let offset: Int
        switch keyCode {
        case 123: offset = -1  // left arrow
        case 124: offset = 1   // right arrow
        default: return Unmanaged.passUnretained(event)
        }

        // Re-enable tap if macOS disabled it
        if let tap = self.tapRef, !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
        }

        Task { @MainActor [weak self] in
            self?.activateAdjacentWindow(offset: offset)
        }

        return nil
    }

    private func activateAdjacentWindow(offset: Int) {
        guard let tracker else { return }
        let windows = tracker.windows

        // Use tracker's focused window, falling back to our last activated window
        // (tracker focus state may lag behind rapid shortcut presses)
        let focusedIndex: Int
        if let idx = windows.firstIndex(where: { $0.isFocused }) {
            focusedIndex = idx
        } else if let lastId = lastActivatedWindowId,
                  let idx = windows.firstIndex(where: { $0.id == lastId }) {
            focusedIndex = idx
        } else {
            return
        }

        let newIndex = focusedIndex + offset
        guard windows.indices.contains(newIndex) else { return }

        let target = windows[newIndex]
        lastActivatedWindowId = target.id

        // Briefly activate our own app to gain activation authority,
        // then activateWindow works just like a panel click.
        NSApp.activate(ignoringOtherApps: true)

        Task {
            try? await tracker.activateWindow(target)
        }
    }
}
