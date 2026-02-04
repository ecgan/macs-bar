@preconcurrency import Cocoa
import os
import MacWindowTracker

final class KeyboardShortcutHandler: @unchecked Sendable {
    @MainActor weak var tracker: WindowTracker?
    @MainActor var currentSpaceState: SpaceBarState?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private let _lock = OSAllocatedUnfairLock<(tapRef: CFMachPort?, tapRunLoop: CFRunLoop?)>(uncheckedState: (nil, nil))
    private var retainedSelf: Unmanaged<KeyboardShortcutHandler>?

    @MainActor func start() {
        let eventMask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        let retained = Unmanaged.passRetained(self)
        retainedSelf = retained
        let userInfo = retained.toOpaque()

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
            retained.release()
            retainedSelf = nil
            print("KeyboardShortcutHandler: Failed to create event tap. Ensure Accessibility permission is granted.")
            return
        }

        eventTap = tap
        _lock.withLock { $0.tapRef = tap }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source

        let thread = Thread { [weak self] in
            let rl = CFRunLoopGetCurrent()!
            self?._lock.withLock { $0.tapRunLoop = rl }
            CFRunLoopAddSource(rl, source!, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "KeyboardShortcutHandler"
        thread.start()
        tapThread = thread
    }

    @MainActor func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopSourceInvalidate(source)
        }
        let rl = _lock.withLock { state -> CFRunLoop? in
            let rl = state.tapRunLoop
            state.tapRef = nil
            state.tapRunLoop = nil
            return rl
        }
        if let rl { CFRunLoopStop(rl) }
        tapThread?.cancel()
        tapThread = nil
        eventTap = nil
        runLoopSource = nil
        retainedSelf?.release()
        retainedSelf = nil
    }

    private func handleCGEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
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
        if let tap = self._lock.withLock({ $0.tapRef }), !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
        }

        Task { @MainActor [weak self] in
            await self?.activateAdjacentWindow(offset: offset)
        }

        return nil
    }

    @MainActor private func activateAdjacentWindow(offset: Int) async {
        guard let tracker, let currentSpaceState else { return }
        let windows = currentSpaceState.windows

        guard let focusedIndex = windows.firstIndex(where: { $0.isFocused }) else { return }

        let newIndex = (focusedIndex + offset + windows.count) % windows.count

        let target = windows[newIndex]

        // Gain activation authority by briefly activating our own app,
        // then poll until macOS has processed the activation.
        NSApp.activate(ignoringOtherApps: true)
        for _ in 0..<20 {
            if NSApp.isActive { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        try? await tracker.activateWindow(target)
    }
}
