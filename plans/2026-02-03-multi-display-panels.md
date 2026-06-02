# Multi-Display Superbar Panels

## Problem

When "Displays have separate Spaces" is ON, each display has its own spaces. Currently, Superbar only shows a panel on the primary display. Users with multiple displays want a panel on each display showing that display's windows.

## Design Decisions

- **One panel per space** (not per display) - panels follow spaces, not displays
- **Use `CGSCopyManagedDisplaySpaces`** - private API to map spaces to displays
- **Panels positioned on correct display** - each space's panel appears on its display

## Implementation

### 1. Add `spacesPerDisplay()` to CGSSpace.swift

```swift
/// Returns current space IDs for each display.
/// Key: display UUID, Value: array of space IDs (first is current/active space)
public func spacesPerDisplay() -> [String: [Int]]
```

Uses `CGSCopyManagedDisplaySpaces` which returns:
```
[
  { "Display Identifier": "UUID-1", "Current Space": {..., "id64": 100}, "Spaces": [...] },
  { "Display Identifier": "UUID-2", "Current Space": {..., "id64": 200}, "Spaces": [...] }
]
```

### 2. Add display UUID to NSScreen mapping

```swift
/// Get the display UUID for an NSScreen
func displayUUID(for screen: NSScreen) -> String?
```

Uses `CGDisplayCreateUUIDFromDisplayID` with screen's `NSScreenNumber`.

### 3. Modify SuperbarApp.swift

**`ensurePanel(forSpace:initialWindows:screen:)`**
- Add `screen: NSScreen` parameter
- Pass screen to `configurePanelStyle`

**`configurePanelStyle(_:screen:)`**
- Take `screen` parameter instead of hardcoding `NSScreen.screens.first`
- Position panel on the specified screen

**`onRefreshComplete` callback**
```swift
if MacWindowTracker.displaysShareSpace() {
    // Shared space: one panel on primary, all windows
    let screen = NSScreen.screens.first!
    updatePanelForSpace(spaceId, windows: windows, screen: screen)
} else {
    // Separate spaces: one panel per display's current space
    let displaySpaces = MacWindowTracker.spacesPerDisplay()
    for screen in NSScreen.screens {
        guard let uuid = displayUUID(for: screen),
              let currentSpaceId = displaySpaces[uuid]?.first else { continue }
        let screenWindows = windows.filter { $0.frame.intersects(screen.frame) }
        updatePanelForSpace(currentSpaceId, windows: screenWindows, screen: screen)
    }
}
```

**Fullscreen methods**
- `shouldHidePanelForFullscreen(windows:screen:)` - add screen parameter
- `updatePanelVisibility(for:windows:screen:)` - add screen parameter
- `isFrontmostAppFullscreen(screen:)` - already has screen parameter
- `isAppControlledFullscreen(window:screen:)` - already has screen parameter

### 4. No changes needed

- `cleanupInvalidPanels()` - already uses `allSpaceIds()`, works for multi-display
- `resetAllPanels()` - clears all panels, refresh recreates them correctly
- `screenDidChange()` - calls `resetAllPanels()`, handles display add/remove

## Behavior Matrix

| Setting | Displays | Panels Created |
|---------|----------|----------------|
| Separate spaces OFF | 1 | 1 on primary |
| Separate spaces OFF | 2 | 1 on primary (shows all windows) |
| Separate spaces ON | 1 | 1 per space on that display |
| Separate spaces ON | 2 | 1 per space, positioned on owning display |

## Edge Cases

- **Display disconnected**: `screenDidChange` triggers `resetAllPanels()`, panels recreated for remaining displays
- **Display connected**: Same as above
- **Space deleted**: `cleanupInvalidPanels()` removes panel for invalid space ID
- **Fullscreen on one display**: Only that display's panel hides, other displays unaffected
