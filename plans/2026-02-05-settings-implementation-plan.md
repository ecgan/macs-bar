# Settings Page Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Settings window with General, Shortcuts, and About tabs accessible from the panel context menu.

**Architecture:** SwiftUI Settings scene with TabView. Settings stored in UserDefaults. Launch at login via SMAppService. Shortcut configuration replaces hardcoded values in KeyboardShortcutHandler.

**Tech Stack:** SwiftUI, AppKit, ServiceManagement (SMAppService), UserDefaults

---

## Task 1: Create Settings Infrastructure

**Files:**
- Create: `app/Sources/MacsBar/Settings/SettingsView.swift`
- Modify: `app/Sources/MacsBar/MacsBarApp.swift:8-12`

**Step 1: Create SettingsView with TabView skeleton**

Create `app/Sources/MacsBar/Settings/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 250)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
```

**Step 2: Create placeholder views for tabs**

Create `app/Sources/MacsBar/Settings/GeneralSettingsView.swift`:

```swift
import SwiftUI

struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Text("General settings placeholder")
        }
        .padding()
    }
}
```

Create `app/Sources/MacsBar/Settings/ShortcutsSettingsView.swift`:

```swift
import SwiftUI

struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Text("Shortcuts settings placeholder")
        }
        .padding()
    }
}
```

Create `app/Sources/MacsBar/Settings/AboutView.swift`:

```swift
import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack {
            Text("About placeholder")
        }
        .padding()
    }
}
```

**Step 3: Update MacsBarApp to use SettingsView**

In `app/Sources/MacsBar/MacsBarApp.swift`, replace lines 8-12:

```swift
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
```

**Step 4: Build and verify**

Run: `cd /Users/engchin/Code/ecgan/macs-bar && swift build`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add app/Sources/MacsBar/Settings/ app/Sources/MacsBar/MacsBarApp.swift
git commit -m "feat(settings): add Settings window infrastructure with tab skeleton"
```

---

## Task 2: Add Settings Menu Item to Context Menu

**Files:**
- Modify: `app/Sources/MacsBar/MacsBarContentView.swift:19-23`

**Step 1: Update context menu with Settings item**

In `app/Sources/MacsBar/MacsBarContentView.swift`, replace the contextMenu block (lines 19-23):

```swift
        .contextMenu {
            Button("Settings...") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            Divider()
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
```

**Step 2: Build and verify**

Run: `cd /Users/engchin/Code/ecgan/macs-bar && swift build`
Expected: BUILD SUCCEEDED

**Step 3: Manual test**

Run app, right-click panel, verify:
- "Settings..." appears above separator
- Clicking it opens Settings window with 3 tabs
- "Quit" still works

**Step 4: Commit**

```bash
git add app/Sources/MacsBar/MacsBarContentView.swift
git commit -m "feat(settings): add Settings menu item to panel context menu"
```

---

## Task 3: Implement General Settings Tab

**Files:**
- Modify: `app/Sources/MacsBar/Settings/GeneralSettingsView.swift`

**Step 1: Implement GeneralSettingsView with toggles**

Replace `app/Sources/MacsBar/Settings/GeneralSettingsView.swift`:

```swift
import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("checkForUpdatesAutomatically") private var checkForUpdates = true

    var body: some View {
        Form {
            Toggle(isOn: $launchAtLogin) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at login")
                    Text("Automatically start Macs Bar when you log in to your Mac")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .onChange(of: launchAtLogin) { _, newValue in
                updateLaunchAtLogin(enabled: newValue)
            }

            Toggle(isOn: $checkForUpdates) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Check for updates automatically")
                    Text("Periodically check for new versions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            syncLaunchAtLoginState()
        }
    }

    private func syncLaunchAtLoginState() {
        let status = SMAppService.mainApp.status
        launchAtLogin = (status == .enabled)
    }

    private func updateLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
            // Revert UI state on failure
            syncLaunchAtLoginState()
        }
    }
}
```

**Step 2: Build and verify**

Run: `cd /Users/engchin/Code/ecgan/macs-bar && swift build`
Expected: BUILD SUCCEEDED

**Step 3: Manual test**

- Open Settings > General tab
- Toggle "Launch at login" on/off
- Verify in System Settings > General > Login Items that Macs Bar appears/disappears
- Toggle "Check for updates" (just stores preference for now)

**Step 4: Commit**

```bash
git add app/Sources/MacsBar/Settings/GeneralSettingsView.swift
git commit -m "feat(settings): implement General tab with launch at login toggle"
```

---

## Task 4: Create Shortcut Storage Model

**Files:**
- Create: `app/Sources/MacsBar/Settings/ShortcutStorage.swift`
- Create: `app/Tests/MacsBarTests/ShortcutStorageTests.swift`

**Step 1: Write the failing test**

Create `app/Tests/MacsBarTests/ShortcutStorageTests.swift`:

```swift
import Testing
@testable import MacsBar

@Suite("Shortcut Storage Tests")
struct ShortcutStorageTests {
    @Test("Default shortcuts are Ctrl+Alt+Arrow keys")
    func defaultShortcuts() {
        let storage = ShortcutStorage(defaults: .init(suiteName: "test-defaults")!)

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
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/engchin/Code/ecgan/macs-bar/app && swift test --filter ShortcutStorageTests`
Expected: FAIL - module 'MacsBar' has no member 'ShortcutStorage'

**Step 3: Write minimal implementation**

Create `app/Sources/MacsBar/Settings/ShortcutStorage.swift`:

```swift
import Foundation
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
        defaults.removeObject(forKey: "keyboardShortcuts")
    }

    private func loadShortcuts() {
        guard let data = defaults.data(forKey: "keyboardShortcuts"),
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
            defaults.set(data, forKey: "keyboardShortcuts")
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/engchin/Code/ecgan/macs-bar/app && swift test --filter ShortcutStorageTests`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add app/Sources/MacsBar/Settings/ShortcutStorage.swift app/Tests/MacsBarTests/ShortcutStorageTests.swift
git commit -m "feat(settings): add ShortcutStorage for persisting keyboard shortcuts"
```

---

## Task 5: Implement Shortcuts Settings Tab

**Files:**
- Modify: `app/Sources/MacsBar/Settings/ShortcutsSettingsView.swift`
- Create: `app/Sources/MacsBar/Settings/ShortcutRecorderView.swift`

**Step 1: Create ShortcutRecorderView component**

Create `app/Sources/MacsBar/Settings/ShortcutRecorderView.swift`:

```swift
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
        case kVK_F1...kVK_F12:
            return "F\(keyCode - kVK_F1 + 1)"
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
```

**Step 2: Implement ShortcutsSettingsView**

Replace `app/Sources/MacsBar/Settings/ShortcutsSettingsView.swift`:

```swift
import SwiftUI

struct ShortcutsSettingsView: View {
    @StateObject private var storage = ShortcutStorage()

    var body: some View {
        Form {
            ForEach(ShortcutAction.allCases, id: \.self) { action in
                ShortcutRecorderView(
                    action: action,
                    shortcut: binding(for: action)
                )
            }

            HStack {
                Spacer()
                Button("Restore Defaults") {
                    storage.resetToDefaults()
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func binding(for action: ShortcutAction) -> Binding<KeyboardShortcut> {
        Binding(
            get: { storage.shortcut(for: action) },
            set: { storage.setShortcut($0, for: action) }
        )
    }
}
```

**Step 3: Build and verify**

Run: `cd /Users/engchin/Code/ecgan/macs-bar && swift build`
Expected: BUILD SUCCEEDED

**Step 4: Manual test**

- Open Settings > Shortcuts tab
- Click "Record" next to a shortcut
- Press a key combination (e.g., Cmd+Shift+J)
- Verify shortcut updates
- Press Escape while recording to cancel
- Click "Restore Defaults" to reset

**Step 5: Commit**

```bash
git add app/Sources/MacsBar/Settings/ShortcutsSettingsView.swift app/Sources/MacsBar/Settings/ShortcutRecorderView.swift
git commit -m "feat(settings): implement Shortcuts tab with shortcut recorder"
```

---

## Task 6: Implement About Tab

**Files:**
- Modify: `app/Sources/MacsBar/Settings/AboutView.swift`

**Step 1: Implement AboutView**

Replace `app/Sources/MacsBar/Settings/AboutView.swift`:

```swift
import SwiftUI

struct AboutView: View {
    private let githubURL = URL(string: "https://github.com/ecgan/macs-bar")!
    private let websiteURL = URL(string: "https://example.com")! // Placeholder

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // App Icon
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 64, height: 64)
            }

            // App Name
            Text("Macs Bar")
                .font(.title)
                .fontWeight(.semibold)

            // Version
            Text("Version \(appVersion)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Copyright
            Text("© 2024 Your Name. All rights reserved.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Links
            HStack(spacing: 16) {
                Button("GitHub") {
                    NSWorkspace.shared.open(githubURL)
                }
                .buttonStyle(.link)

                Button("Website") {
                    NSWorkspace.shared.open(websiteURL)
                }
                .buttonStyle(.link)
            }
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}
```

**Step 2: Build and verify**

Run: `cd /Users/engchin/Code/ecgan/macs-bar && swift build`
Expected: BUILD SUCCEEDED

**Step 3: Manual test**

- Open Settings > About tab
- Verify app icon, name, version display
- Click GitHub link - should open browser
- Click Website link - should open browser (placeholder)

**Step 4: Commit**

```bash
git add app/Sources/MacsBar/Settings/AboutView.swift
git commit -m "feat(settings): implement About tab with app info and links"
```

---

## Task 7: Integrate ShortcutStorage with KeyboardShortcutHandler

**Files:**
- Modify: `app/Sources/MacsBar/KeyboardShortcutHandler.swift`
- Modify: `app/Sources/MacsBar/MacsBarApp.swift`

**Step 1: Update KeyboardShortcutHandler to use ShortcutStorage**

Replace `app/Sources/MacsBar/KeyboardShortcutHandler.swift`:

```swift
@preconcurrency import Cocoa
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
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))

        // Convert CGEventFlags to NSEvent.ModifierFlags for comparison
        var modifiers: NSEvent.ModifierFlags = []
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }

        // Check against configured shortcuts
        var matchedAction: ShortcutAction?

        // Read shortcuts on main actor
        let shortcuts = DispatchQueue.main.sync { [weak self] () -> [ShortcutAction: KeyboardShortcut]? in
            self?.shortcutStorage?.shortcuts
        }

        for action in ShortcutAction.allCases {
            let shortcut = shortcuts?[action] ?? KeyboardShortcut(
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
```

**Step 2: Create shared ShortcutStorage instance in AppDelegate**

In `app/Sources/MacsBar/MacsBarApp.swift`, add to AppDelegate class (after line 20):

```swift
    let shortcutStorage = ShortcutStorage()
```

And in `applicationDidFinishLaunching` (after line 38, before `keyboardShortcutHandler.start()`):

```swift
        keyboardShortcutHandler.shortcutStorage = shortcutStorage
```

**Step 3: Build and verify**

Run: `cd /Users/engchin/Code/ecgan/macs-bar && swift build`
Expected: BUILD SUCCEEDED

**Step 4: Run all tests**

Run: `cd /Users/engchin/Code/ecgan/macs-bar/app && swift test`
Expected: All tests PASS

**Step 5: Manual test**

- Change shortcuts in Settings
- Verify new shortcuts work immediately
- Restart app, verify shortcuts persist

**Step 6: Commit**

```bash
git add app/Sources/MacsBar/KeyboardShortcutHandler.swift app/Sources/MacsBar/MacsBarApp.swift
git commit -m "feat(settings): integrate ShortcutStorage with KeyboardShortcutHandler"
```

---

## Task 8: Final Verification and Cleanup

**Step 1: Run full build**

Run: `cd /Users/engchin/Code/ecgan/macs-bar && swift build`
Expected: BUILD SUCCEEDED with no warnings

**Step 2: Run all tests**

Run: `cd /Users/engchin/Code/ecgan/macs-bar/app && swift test`
Expected: All tests PASS

**Step 3: Manual end-to-end test**

1. Launch app
2. Right-click panel → Settings... → window opens
3. General tab: toggle Launch at login, verify in System Settings
4. Shortcuts tab: change a shortcut, verify it works
5. About tab: verify info displays, links work
6. Close settings, reopen → settings persist
7. Quit and relaunch → all settings persist

**Step 4: Commit design and plan docs together**

```bash
git add docs/plans/2026-02-05-settings-page-design.md docs/plans/2026-02-05-settings-implementation-plan.md
git commit -m "docs: add settings page design and implementation plan"
```
