# Settings Page Design

## Overview

Add a Settings window to Macs Bar accessible via the panel's right-click context menu. The settings window follows standard macOS conventions using SwiftUI's native `Settings` scene with tab-based navigation.

## Access Point

- Right-click on panel → "Settings..." menu item (above separator and "Quit")
- Opens standard macOS Settings window
- Uses `NSApp.activate(ignoringOtherApps: true)` to ensure window surfaces for LSUIElement app

## Window Implementation

Use custom `NSWindow` with `NSHostingController` via `SettingsWindowController`:

```swift
// SettingsWindowController.swift
class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func showSettings() {
        // Creates NSWindow with SettingsView embedded via NSHostingController
    }
}
```

**Why custom NSWindow (not SwiftUI Settings scene):**

- SwiftUI `Settings` scene does NOT work with LSUIElement apps (`.accessory` activation policy)
- When using `@NSApplicationDelegateAdaptor` with `.accessory` policy, SwiftUI's scene lifecycle isn't fully active
- The `showSettingsWindow:` action returns `true` but no window is created
- Custom NSWindow provides full control and works reliably with any app type

## Tab Structure

Three tabs: **General** | **Shortcuts** | **About**

### General Tab

Standard form layout with two toggles:

```
┌─────────────────────────────────────────┐
│ General │ Shortcuts │ About             │
├─────────────────────────────────────────┤
│                                         │
│  ☑ Launch at login                      │
│    Automatically start Macs Bar when    │
│    you log in to your Mac               │
│                                         │
│  ☑ Check for updates automatically      │
│    Periodically check for new versions  │
│                                         │
└─────────────────────────────────────────┘
```

**Implementation:**

- **Launch at login:** Uses `SMAppService.mainApp` (ServiceManagement framework, macOS 13+) to register/unregister login item. State managed by system.

- **Check for updates:** Stores preference in `UserDefaults`. Actual update checking mechanism deferred (just the toggle and stored preference for now).

### Shortcuts Tab

Form with configurable shortcuts using "Record Shortcut" pattern:

```
┌─────────────────────────────────────────┐
│ General │ Shortcuts │ About             │
├─────────────────────────────────────────┤
│                                         │
│  Switch to Previous Window              │
│  ┌──────────────────┐  ┌──────────────┐ │
│  │ ⌃⌥←              │  │   Record     │ │
│  └──────────────────┘  └──────────────┘ │
│                                         │
│  Switch to Next Window                  │
│  ┌──────────────────┐  ┌──────────────┐ │
│  │ ⌃⌥→              │  │   Record     │ │
│  └──────────────────┘  └──────────────┘ │
│                                         │
│           [ Restore Defaults ]          │
│                                         │
└─────────────────────────────────────────┘
```

**Behavior:**
- Click "Record" → button shows "Press shortcut..." and captures next key combo
- Press Escape to cancel recording
- Invalid shortcuts (reserved system shortcuts) show brief error
- "Restore Defaults" resets to Ctrl+Alt+Left/Right

**Storage:**
- Shortcuts stored in `UserDefaults` as encoded key codes + modifiers
- `KeyboardShortcutHandler` reads from UserDefaults on init and when settings change

**Conflict Detection:**
- If user records a shortcut already used by another action, prompt to reassign or cancel

### About Tab

Centered content, standard macOS About panel style:

```
┌─────────────────────────────────────────┐
│ General │ Shortcuts │ About             │
├─────────────────────────────────────────┤
│                                         │
│              [App Icon]                 │
│               64x64                     │
│                                         │
│             Macs Bar                    │
│           Version 1.0.0                 │
│                                         │
│   © 2024 Your Name. All rights reserved.│
│                                         │
│      ┌──────────┐  ┌──────────┐         │
│      │  GitHub  │  │ Website  │         │
│      └──────────┘  └──────────┘         │
│                                         │
└─────────────────────────────────────────┘
```

**Implementation:**
- App icon from `NSApp.applicationIconImage`
- Version from `Bundle.main.infoDictionary["CFBundleShortVersionString"]`
- Links open in default browser via `NSWorkspace.shared.open(url)`

**Placeholder values:**
- Copyright: placeholder (to be updated)
- GitHub: https://github.com/ecgan/macs-bar
- Website: placeholder (to be updated)

## Context Menu Update

In `MacsBarContentView.swift`, update panel context menu:

```
Right-click menu:
├── Settings...    → opens Settings window
├── ─────────────  → separator
└── Quit           → terminates app
```

**Trigger mechanism:**
```swift
Button("Settings...") {
    if #available(macOS 14, *) {
        NSApp.activate()
    } else {
        NSApp.activate(ignoringOtherApps: true)
    }
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
}
```

## File Structure

```
app/Sources/MacsBar/
├── MacsBarApp.swift              (add Settings scene)
├── MacsBarContentView.swift      (update context menu)
├── Settings/
│   ├── SettingsView.swift        (TabView container)
│   ├── GeneralSettingsView.swift
│   ├── ShortcutsSettingsView.swift
│   └── AboutView.swift
├── SpaceBarState.swift           (unchanged)
└── KeyboardShortcutHandler.swift (read shortcuts from UserDefaults)
```

## Dependencies

- `ServiceManagement` framework (for launch at login via `SMAppService`)

## Future Considerations

- Actual update checking implementation (Sparkle framework or custom)
- Additional general settings as needed
- More shortcut actions as app features expand
