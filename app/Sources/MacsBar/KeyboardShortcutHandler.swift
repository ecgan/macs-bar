@preconcurrency import Cocoa
import Combine
import os
import MacWindowTracker

final class KeyboardShortcutHandler: @unchecked Sendable {
    @MainActor weak var tracker: WindowTracker?
    @MainActor var currentSpaceState: SpaceBarState?
    @MainActor var shortcutStorage: ShortcutStorage?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private let _lock = OSAllocatedUnfairLock<(tapRef: CFMachPort?, tapRunLoop: CFRunLoop?)>(uncheckedState: (nil, nil))
    private let _shortcutsCache = OSAllocatedUnfairLock<[ShortcutAction: KeyboardShortcut]>(uncheckedState: [:])
    private var shortcutsCancellable: AnyCancellable?
    private var retainedSelf: Unmanaged<KeyboardShortcutHandler>?

    @MainActor func start() {
        // Cache shortcuts for lock-protected access from the event tap thread.
        // This avoids DispatchQueue.main.sync on every keypress.
        if let storage = shortcutStorage {
            let initial = storage.shortcuts
            _shortcutsCache.withLock { $0 = initial }
            shortcutsCancellable = storage.$shortcuts.sink { [weak self] newShortcuts in
                self?._shortcutsCache.withLock { $0 = newShortcuts }
            }
        }

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
        shortcutsCancellable?.cancel()
        shortcutsCancellable = nil

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
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))

        // Convert CGEventFlags to NSEvent.ModifierFlags for comparison
        var modifiers: NSEvent.ModifierFlags = []
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }

        // Check against configured shortcuts (read from lock-protected cache, no main thread hop)
        var matchedAction: ShortcutAction?
        let shortcuts = _shortcutsCache.withLock { $0 }

        for action in ShortcutAction.allCases {
            let shortcut = shortcuts[action] ?? KeyboardShortcut(
                keyCode: action.defaultKeyCode,
                modifiers: action.defaultModifiers
            )
            if keyCode == shortcut.keyCode && modifiers == shortcut.modifiers {
                matchedAction = action
                break
            }
        }

        guard let action = matchedAction else {
            return Unmanaged.passUnretained(event)
        }

        // Re-enable tap if macOS disabled it
        if let tap = self._lock.withLock({ $0.tapRef }), !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
        }

        let offset: Int = (action == .previousWindow) ? -1 : 1

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

        try? await tracker.activateWindow(target)
    }
}
