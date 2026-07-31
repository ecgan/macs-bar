@preconcurrency import Cocoa
import Combine
import os
import MacWindowTracker

final class KeyboardShortcutHandler: @unchecked Sendable {
    @MainActor weak var tracker: WindowTracker?
    @MainActor var currentSpaceState: SpaceBarState?
    @MainActor var shortcutStorage: ShortcutStorage?
    @MainActor var onToggleAutoHide: (() -> Void)?
    @MainActor var onNavigationModifiersChanged: ((Bool) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private let _lock = OSAllocatedUnfairLock<(tapRef: CFMachPort?, tapRunLoop: CFRunLoop?)>(uncheckedState: (nil, nil))
    private let _shortcutsCache = OSAllocatedUnfairLock<[ShortcutAction: KeyboardShortcut]>(uncheckedState: [:])
    private let _modifierState = OSAllocatedUnfairLock<(
        modifiers: NSEvent.ModifierFlags,
        navigationModifiersHeld: Bool,
        isRunning: Bool
    )>(uncheckedState: ([], false, false))
    private var shortcutsCancellable: AnyCancellable?
    private var retainedSelf: Unmanaged<KeyboardShortcutHandler>?

    @MainActor func start() {
        // Cache shortcuts for lock-protected access from the event tap thread.
        // This avoids DispatchQueue.main.sync on every keypress.
        if let storage = shortcutStorage {
            let initial = storage.shortcuts
            _shortcutsCache.withLock { $0 = initial }
            shortcutsCancellable = storage.$shortcuts.sink { [weak self] newShortcuts in
                guard let self else { return }
                self._shortcutsCache.withLock { $0 = newShortcuts }
                self.reevaluateNavigationModifiers()
            }
        }

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let retained = Unmanaged.passRetained(self)
        retainedSelf = retained
        let userInfo = retained.toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, eventType, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let handler = Unmanaged<KeyboardShortcutHandler>.fromOpaque(userInfo).takeUnretainedValue()
                return handler.handleCGEvent(event, type: eventType)
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

        _modifierState.withLock { $0.isRunning = true }
        updateNavigationModifiers(
            Self.modifierFlags(from: CGEventSource.flagsState(.combinedSessionState))
        )
    }

    @MainActor func stop() {
        shortcutsCancellable?.cancel()
        shortcutsCancellable = nil

        let wereNavigationModifiersHeld = _modifierState.withLock { state in
            let wereHeld = state.navigationModifiersHeld
            state.modifiers = []
            state.navigationModifiersHeld = false
            state.isRunning = false
            return wereHeld
        }
        if wereNavigationModifiersHeld {
            onNavigationModifiersChanged?(false)
        }

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

    private func handleCGEvent(
        _ event: CGEvent,
        type: CGEventType
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = _lock.withLock({ $0.tapRef }) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let modifiers = Self.modifierFlags(from: event.flags)

        if type == .flagsChanged {
            updateNavigationModifiers(modifiers)
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))

        // Check against configured shortcuts (read from lock-protected cache, no main thread hop)
        var matchedAction: ShortcutAction?
        let shortcuts = _shortcutsCache.withLock { $0 }

        for action in ShortcutAction.allCases {
            let shortcut = KeyboardShortcutMatcher.resolvedShortcut(
                for: action,
                overrides: shortcuts
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

        switch action {
        case .previousWindow:
            Task { @MainActor [weak self] in
                await self?.activateAdjacentWindow(offset: -1)
            }
        case .nextWindow:
            Task { @MainActor [weak self] in
                await self?.activateAdjacentWindow(offset: 1)
            }
        case .toggleAutoHide:
            Task { @MainActor [weak self] in
                self?.onToggleAutoHide?()
            }
        }

        return nil
    }

    private func reevaluateNavigationModifiers() {
        let modifiers = _modifierState.withLock { $0.modifiers }
        updateNavigationModifiers(modifiers)
    }

    private func updateNavigationModifiers(_ modifiers: NSEvent.ModifierFlags) {
        let shortcuts = _shortcutsCache.withLock { $0 }
        let areHeld = KeyboardShortcutMatcher.navigationModifiersExactlyMatch(
            modifiers,
            overrides: shortcuts
        )
        let shouldNotify = _modifierState.withLock { state in
            state.modifiers = modifiers
            guard state.isRunning, state.navigationModifiersHeld != areHeld else {
                return false
            }
            state.navigationModifiersHeld = areHeld
            return true
        }

        guard shouldNotify else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let isCurrent = self._modifierState.withLock {
                $0.isRunning && $0.navigationModifiersHeld == areHeld
            }
            guard isCurrent else { return }
            self.onNavigationModifiersChanged?(areHeld)
        }
    }

    private static func modifierFlags(from flags: CGEventFlags) -> NSEvent.ModifierFlags {
        var modifiers: NSEvent.ModifierFlags = []
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        return modifiers
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
