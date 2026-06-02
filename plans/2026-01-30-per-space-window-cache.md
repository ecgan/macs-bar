# Per-Space Window Cache Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate the taskbar flicker when switching macOS desktop spaces by caching windows per-space and instantly swapping on space change.

**Architecture:** Add a private `CGSGetActiveSpace` bridge to get the current space ID. WindowTracker maintains a `[Int: [TrackedWindow]]` cache keyed by space ID. On space change, it immediately swaps `self.windows` to the cached list for the new space (or `[]`), then performs the normal full refresh. RefreshManager gets a new `refreshImmediately` path for space changes that bypasses debounce for the initial swap.

**Tech Stack:** Swift, CoreGraphics private API (`CGSGetActiveSpace`), SwiftUI/Combine (existing)

---

### Task 1: Add CGSGetActiveSpace Private API Bridge

**Files:**
- Create: `Sources/MacWindowTracker/CGWindow/CGSSpace.swift`

**Step 1: Create the bridge file**

```swift
import CoreGraphics

/// Private CoreGraphics API to get the active Space ID.
/// Used by window managers (yabai, AeroSpace) — stable across macOS versions.
@_silgen_name("CGSGetActiveSpace")
func CGSGetActiveSpace(_ connection: Int32) -> Int

/// Private CoreGraphics API to get the default connection.
@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> Int32

/// Get the current macOS Space ID.
func currentSpaceId() -> Int {
    CGSGetActiveSpace(CGSMainConnectionID())
}
```

**Step 2: Verify it compiles**

Run: `cd /Users/engchin/Code/MacWindowTracker && swift build 2>&1 | tail -5`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/MacWindowTracker/CGWindow/CGSSpace.swift
git commit -m "Add CGSGetActiveSpace private API bridge for space identification"
```

---

### Task 2: Add Per-Space Cache to WindowTracker

**Files:**
- Modify: `Sources/MacWindowTracker/Core/WindowTracker.swift`

**Step 1: Add cache state properties**

Add after `private var monitorCancellable: AnyCancellable?` (line 30):

```swift
/// Cache of windows per desktop space, keyed by space ID
private var windowsBySpace: [Int: [TrackedWindow]] = [:]

/// The space ID we were on before the current refresh
private var currentSpaceId: Int = 0
```

**Step 2: Initialize currentSpaceId in start()**

Add at the end of `start()`, just before the `await performRefresh(event: .manual)` call (line 80):

```swift
// Record initial space
currentSpaceId = MacWindowTracker.currentSpaceId()
```

**Step 3: Handle space change in performRefresh**

Replace the `performRefresh` method (lines 178-250) with:

```swift
private func performRefresh(event: RefreshEvent) async {
    // On space change, immediately swap to cached windows for the new space
    if event == .spaceChange {
        // Save current windows under the old space
        if currentSpaceId != 0 {
            windowsBySpace[currentSpaceId] = windows
        }
        // Switch to new space
        let newSpaceId = MacWindowTracker.currentSpaceId()
        currentSpaceId = newSpaceId
        // Instantly swap to cached windows (or empty if first visit)
        self.windows = windowsBySpace[newSpaceId] ?? []
    }

    // Get all on-screen windows from CGWindowList
    let cgWindows = CGWindowList.onScreenWindows()

    // Get focused window via AX
    let focusedInfo = try? await appObserverManager?.getFocusedWindow()
    let newFocusedId = focusedInfo?.windowId

    // Build AX title lookup for windows missing CGWindowName
    let axTitles = Self.axTitleLookup(for: cgWindows)

    // Build AX subrole lookup to filter out popup/dropdown windows
    let standardWindowIds = Self.axStandardWindowIds(for: cgWindows)

    // Build tracked windows list
    var newWindows: [TrackedWindow] = []
    var appCache: [pid_t: NSRunningApplication] = [:]

    for cgWindow in cgWindows {
        // Skip non-standard windows (popups, dropdowns, dialogs, etc.)
        if !standardWindowIds.contains(cgWindow.windowId) {
            continue
        }
        // Apply size filter
        guard cgWindow.bounds.width >= minimumWindowSize.width,
              cgWindow.bounds.height >= minimumWindowSize.height else {
            continue
        }

        // Apply title filter
        if !includeUntitledWindows && (cgWindow.title?.isEmpty ?? true) {
            continue
        }

        // Skip windows from non-regular apps.
        let app: NSRunningApplication? = appCache[cgWindow.ownerPid] ?? {
            let resolved = NSRunningApplication(processIdentifier: cgWindow.ownerPid)
            if let resolved { appCache[cgWindow.ownerPid] = resolved }
            return resolved
        }()
        guard let app, app.activationPolicy == .regular else {
            continue
        }

        let bundleId = app.bundleIdentifier
        let monitorId = monitorManager.monitorId(forWindowFrame: cgWindow.bounds)

        let trackedWindow = TrackedWindow(
            id: cgWindow.windowId,
            title: cgWindow.title ?? axTitles[cgWindow.windowId],
            appName: cgWindow.ownerName,
            appBundleId: bundleId,
            appPid: cgWindow.ownerPid,
            frame: cgWindow.bounds,
            monitorId: monitorId,
            isFocused: cgWindow.windowId == newFocusedId
        )

        newWindows.append(trackedWindow)
    }

    // Sort by window ID (lower IDs were created earlier)
    newWindows.sort { $0.id < $1.id }

    // Update published state and cache
    self.windows = newWindows
    self.focusedWindowId = newFocusedId
    windowsBySpace[currentSpaceId] = newWindows
}
```

**Step 4: Make RefreshEvent equatable**

In `Sources/MacWindowTracker/Refresh/RefreshManager.swift`, change line 5:

```swift
public enum RefreshEvent: Sendable, Equatable {
```

**Step 5: Verify it compiles**

Run: `cd /Users/engchin/Code/MacWindowTracker && swift build 2>&1 | tail -5`
Expected: Build succeeds

**Step 6: Commit**

```bash
git add Sources/MacWindowTracker/Core/WindowTracker.swift Sources/MacWindowTracker/Refresh/RefreshManager.swift
git commit -m "Add per-space window cache to eliminate flicker on space switch"
```

---

### Task 3: Bypass Debounce for Space Change

**Files:**
- Modify: `Sources/MacWindowTracker/Refresh/RefreshManager.swift`

**Step 1: Use refreshNow for space changes**

Change the space change observer (lines 115-118) from `scheduleRefresh` to `refreshNow`:

```swift
// Space change - windows may appear/disappear
workspaceObservers.append(
    nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in self?.refreshNow(.spaceChange) }
    }
)
```

This bypasses the 50ms debounce so the cache swap happens as fast as possible.

**Step 2: Verify it compiles**

Run: `cd /Users/engchin/Code/MacWindowTracker && swift build 2>&1 | tail -5`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/MacWindowTracker/Refresh/RefreshManager.swift
git commit -m "Bypass debounce for space changes for instant cache swap"
```

---

### Task 4: Clean Up Stale Cache Entries

**Files:**
- Modify: `Sources/MacWindowTracker/Core/WindowTracker.swift`

**Step 1: Clear cache on stop()**

In the `stop()` method, add after `focusedWindowId = nil` (line 95):

```swift
windowsBySpace.removeAll()
currentSpaceId = 0
```

**Step 2: Verify it compiles**

Run: `cd /Users/engchin/Code/MacWindowTracker && swift build 2>&1 | tail -5`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/MacWindowTracker/Core/WindowTracker.swift
git commit -m "Clear per-space cache on tracker stop"
```

---

### Task 5: Build SuperbarApp and Manual Test

**Step 1: Build SuperbarApp**

Run: `cd /Users/engchin/Code/MacWindowTracker && swift build --product SuperbarApp 2>&1 | tail -10`
Expected: Build succeeds

**Step 2: Manual test plan**

1. Launch SuperbarApp
2. Open several windows on Space 1
3. Switch to Space 2 — the superbar should instantly show empty (or cached Space 2 windows) with no flicker of Space 1 windows
4. Open some windows on Space 2
5. Switch back to Space 1 — should instantly show Space 1 windows with no flicker
6. Switch back to Space 2 — should instantly show Space 2 windows (cached)

**Step 3: Final commit if any fixes needed**
