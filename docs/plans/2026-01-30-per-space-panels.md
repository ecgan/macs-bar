# Separate NSPanel Per Desktop Space

## Goal

Eliminate taskbar flicker during space transitions by having one NSPanel per space. Each panel is pinned to its space, so during the transition animation the old panel slides away with correct data and the new panel slides in with its own (cached) data.

## Scope limitation: single-display only

This plan targets single-display setups. macOS spaces are per-display — each display has its own active space, and `CGSGetActiveSpace` returns only one of them (the main display's). Supporting multi-monitor would require `CGSManagedDisplayGetCurrentSpace` per display, per-display panel dictionaries, and knowing which display a space belongs to. That is deferred to a follow-up.

**Warning (Multi-Monitor Artifacts):**
1. **Ghost Panels:** On multi-monitor setups, focusing a space on a secondary display may cause `CGSGetActiveSpace` to return that space ID. Since this plan forces panels to the primary screen (`NSScreen.screens.first`), a "ghost panel" (likely empty) may appear on the main display for the secondary space.
2. **Over-Retention:** `MacWindowTracker.allSpaceIds()` returns spaces for *all* displays. `cleanupInvalidPanels` will therefore preserve panels for secondary monitors even if they are not relevant to the main display.
These artifacts are known limitations of the single-display scope and are accepted for this iteration.

## Key invariant: CGWindowList is space-filtered (per display)

`CGWindowListCopyWindowInfo` with `.optionOnScreenOnly` returns windows on the active space of **each** connected display. This is documented in `CGWindowList.swift:18`. For a single-display setup, this equals the current space. For multi-display, it includes the active space of every monitor. The library returns this raw list. The "App-Side Scope Enforcement" in this plan filters this list to the primary screen (`NSScreen.screens.first`), effectively narrowing the data to the main display's active space.

## Key invariant: space changes trigger immediate refresh

`RefreshManager` subscribes to `NSWorkspace.activeSpaceDidChangeNotification` and calls `refreshNow(.spaceChange)`, bypassing the 50ms debounce (see `RefreshManager.swift:114–119`). This means `onRefreshComplete` fires immediately (within one run loop turn) after a space change — it is notification-driven, not polling-driven. The periodic 2-second timer is a safety net only. All panel creation and state updates happen inside `onRefreshComplete`, which fires within one run loop turn of the space-change notification. No separate space-change observer in AppDelegate is needed because RefreshManager's observer feeds directly into `onRefreshComplete` via `performRefresh`.

## Space ID stability caveat

macOS space IDs (from `CGSGetActiveSpace`) are not guaranteed stable across display configuration changes or reboots. When a display is connected or disconnected, macOS may reorganize spaces and assign new IDs. A panel's `spaceId` (assigned at creation) can become permanently stale. This plan does **not** attempt to track space renumbering — instead, it relies on cleanup to discard orphaned panels and creates fresh ones for new space IDs. This means a display change effectively resets all panels, which is acceptable because the user's window arrangement also changes.

## Note: Library API is internal

MacWindowTracker is not yet a public/published library. There are no external consumers. Breaking changes to `@Published` properties, method signatures, or callback APIs do not require semver versioning or deprecation periods. This plan freely removes `@Published` and restructures the API surface without backward-compatibility concern.

## Prerequisite: Proof-of-concept for panel sliding

Before implementing anything, validate the core assumption: that an NSPanel at `.statusBar` level, pinned to a single space via `CGSMoveWindowToSpace` (without `.canJoinAllSpaces`), actually participates in the macOS space-transition slide animation.

**POC steps:**
1. Create a minimal app with two NSPanels at `.statusBar` level, each with `.ignoresCycle` and `.fullScreenAuxiliary` only (no `.canJoinAllSpaces`, no `.stationary`).
2. Pin each panel to a different space via `CGSMoveWindowToSpace`.
3. Switch spaces and observe whether panels slide with the transition or pop in/out.

**Also test:** Create a panel for a space you're NOT currently on (the rapid-switching case). `orderFrontRegardless` on a non-visible space is unusual — some macOS versions may defer the ordering until the space becomes active, causing the panel to appear late or not at all. This must work for lazy creation to be viable.

**If panels don't slide:** The entire per-space panel approach produces worse behavior than the current single-panel solution. Abort this plan and investigate alternatives (e.g., pre-rendering cached content into the single panel on space change).

**If panels slide but with artifacts** (e.g., z-order issues, brief flicker at edges): Document the artifacts and decide if they're acceptable before proceeding.

This is the #1 risk for this plan.

## Approach

- Remove `.canJoinAllSpaces` from panels
- Create panels lazily as the user visits each space
- Each panel has its own `SpaceBarState` observable object holding that space's windows
- WindowTracker delivers paired (spaceId, focusedWindowId, windows) snapshots via a dedicated callback — not via `@Published` — to avoid Combine `willSet` ordering issues
- Panel-to-space binding uses `CGSMoveWindowToSpace` private API for deterministic space assignment

## Changes

### 1. Add space-aware refresh callback to WindowTracker

**File:** `Sources/MacWindowTracker/Core/WindowTracker.swift`

**Thread Safety:** `WindowTracker` is already annotated with `@MainActor` (line 12). No change needed. All updates and callbacks already occur on the main thread.

**Problem with `@Published`:** Combine's `@Published` fires on `willSet`, meaning when `$currentSpaceId` emits, `self.currentSpaceId` still holds the old value. Two separate `@Published` subscriptions cannot guarantee paired reads.

**Solution:** Add a callback-based notification that delivers the space ID and windows as an atomic snapshot:

```swift
/// Callback delivering (spaceId, windows) as an atomic snapshot after each refresh.
public var onRefreshComplete: ((_ spaceId: Int, _ windows: [TrackedWindow]) -> Void)?
```

At the end of `performRefresh`, after setting `self.windows` and `self.focusedWindowId`:

```swift
onRefreshComplete?(currentSpaceId, newWindows)
```

This fires after `currentSpaceId` and `windows` are fully stored (`didSet` equivalent), so the consumer always gets a consistent snapshot.

**Why no `focusedWindowId` in the callback:** The focused window is already embedded as `TrackedWindow.isFocused` on each window in the array. `KeyboardShortcutHandler` finds the focused window by scanning the array (linear scan over a small list). This is intentional — a separate `focusedWindowId` parameter would be redundant and create a risk of inconsistency.

**Remove `@Published` from properties:** Since all consumers now go through either `onRefreshComplete` (AppDelegate) or `SpaceBarState` (SwiftUI views), the `@Published` wrapper on `windows` and `focusedWindowId` is no longer needed. Remove `@Published` and make them `public private(set) var` to avoid maintaining an orphaned reactive API.

**Also:** Make `currentSpaceId` `public private(set)` (not `@Published`) for read access.
> **Note:** Consumers should prefer the data delivered via `onRefreshComplete` to guarantee atomic snapshots of (spaceId, windows). The `currentSpaceId` property on `WindowTracker` reflects the last refresh and may not be synchronized with the precise moment of a callback if internal threading changes. Use the property for "pull" checks (like in `activeSpaceId` logic), but use the callback for "push" UI updates.

**File:** `Sources/MacWindowTracker/CGWindow/CGSSpace.swift`

- Change `func currentSpaceId()` to `public func currentSpaceId()`

**Remove library-level `windowsBySpace` cache:** The per-space cache in `WindowTracker.performRefresh()` (introduced in commit 677be63) is superseded by `SpaceBarState` — each panel now holds its own window list. Keeping both means windows are stored three times (library cache, SpaceBarState, SwiftUI view state). Remove the `windowsBySpace` dictionary and the cache-swap logic from `performRefresh`. The library should just report what `CGWindowListCopyWindowInfo` returns; the app layer handles per-space state.

**AppDelegate observer audit:** The current AppDelegate (`SuperbarApp.swift`) has no `activeSpaceDidChangeNotification` observer — space-change handling is entirely within `RefreshManager` (line 114–119 of `RefreshManager.swift`). The only notification observer in AppDelegate is `NSApplication.didChangeScreenParametersNotification` for `screenDidChange`. Remove `windowsCancellable` (the `tracker.$windows` Combine subscription) and the `observeMaximizedWindows` method, since `onRefreshComplete` replaces both.

### 2. Add `CGSMoveWindowToSpace` and `CGSCopySpaces` bridges

**File:** `Sources/MacWindowTracker/CGWindow/CGSSpace.swift`

Add alongside existing private API bridges:

```swift
@_silgen_name("CGSMoveWindowToSpace")
func CGSMoveWindowToSpace(_ connection: Int32, _ window: UInt32, _ space: Int)

@_silgen_name("CGSCopySpaces")
func CGSCopySpaces(_ connection: Int32, _ type: Int32) -> CFArray

extension MacWindowTracker {
    /// Move an NSWindow to a specific space.
    public static func moveWindowToSpace(_ window: NSWindow, spaceId: Int) {
        CGSMoveWindowToSpace(CGSMainConnectionID(), UInt32(window.windowNumber), spaceId)
    }

    /// Get the list of all valid space IDs.
    public static func allSpaceIds() -> [Int] {
        // Space type constants (from reverse engineering, not stable across macOS versions):
        //   1 = current spaces, 2 = all spaces, 5 = user spaces, 7 = user + fullscreen spaces
        // We use 7 to include fullscreen spaces in cleanup (a panel on a fullscreen space is valid).
        //
        // DEFENSIVE FALLBACK: If CGSCopySpaces returns empty or nil (e.g., the constant's meaning
        // changed in a new macOS version), return an empty array. The caller (cleanupInvalidPanels)
        // must treat an empty result as "unknown" and skip cleanup entirely — NOT as "all spaces
        // are invalid" (which would destroy every panel).
        guard let spaces = CGSCopySpaces(CGSMainConnectionID(), 7) as? [Int], !spaces.isEmpty else { return [] }
        return spaces
    }
}
```

This deterministically pins a panel to a space and allows robust cleanup of deleted spaces.

**Caveat on private API types:** The `CGSMoveWindowToSpace` signature is derived from reverse engineering (yabai, Hammerspoon, etc.), not public headers. The parameter types (`Int32` for connection, `UInt32` for window, `Int` for space) are stable on macOS 13–15 but could change. If the app crashes on launch with `EXC_BAD_ACCESS` in `CGSMoveWindowToSpace`, suspect a type mismatch. Verify against the macOS version under test. The same caveat applies to the existing `CGSGetActiveSpace` and `CGSMainConnectionID` bridges.

### 3. Create `SpaceBarState` observable

**New file:** `Examples/SuperbarApp/Sources/SpaceBarState.swift`

```swift
@MainActor
class SpaceBarState: ObservableObject {
    let spaceId: Int
    @Published var windows: [TrackedWindow] = []
    private let onActivate: (TrackedWindow) async -> Void

    init(spaceId: Int, onActivate: @escaping @MainActor (TrackedWindow) async -> Void) {
        self.spaceId = spaceId
        self.onActivate = onActivate
    }

    func activateWindow(_ window: TrackedWindow) async {
        // We do NOT guard against space mismatch here.
        // If the user clicks a window on a sliding-out panel, we should attempt activation.
        await onActivate(window)
    }
}
```

No Combine subscriptions. Data is pushed in by AppDelegate. Decoupled from `WindowTracker`.

### 4. Update `SuperbarContentView` to use `SpaceBarState`

**File:** `Examples/SuperbarApp/Sources/SuperbarContentView.swift`

**Full audit of tracker usage in current code:**

- `SuperbarContentView` (line 5): `@ObservedObject var tracker: WindowTracker` — used for `tracker.windows` (line 11)
- `SuperbarItem` (line 22–23): `let tracker: WindowTracker` — used only for `tracker.activateWindow(window)` (line 56)
- `AppIcon` (line 64): no tracker dependency — uses only `bundleId: String?`
- Focus highlight (line 42): `window.isFocused` is a property of `TrackedWindow`, not read from tracker

**Changes:**

- Change `@ObservedObject var tracker: WindowTracker` → `@ObservedObject var state: SpaceBarState`
- Read `state.windows` instead of `tracker.windows`
- `SuperbarItem` takes `state: SpaceBarState` instead of `tracker: WindowTracker`, calls `state.activateWindow(window)`
- No changes needed to `AppIcon` or focus highlighting (`window.isFocused` is embedded in `TrackedWindow`)

### 5. Refactor AppDelegate for per-space panels

**File:** `Examples/SuperbarApp/Sources/SuperbarApp.swift`

Replace:

- `var panel: NSPanel?` → `var panels: [Int: NSPanel]` + `var spaceStates: [Int: SpaceBarState]`
- Remove `windowsCancellable` and `observeMaximizedWindows` method
- Add `var activeSpaceId: Int = 0` instance property

#### Startup (Immediate UI)

In `applicationDidFinishLaunching`:

```swift
// Create an initial panel for the current space immediately.
// It starts empty (blank bar) but the first refresh fires within one run-loop turn
// of applicationDidFinishLaunching (triggered by RefreshManager's startup refresh),
// so the gap is typically <50ms — not perceptible. No loading indicator is needed.
// If this gap proves visible in practice, consider pre-populating from CGWindowList
// synchronously here, but that adds complexity for minimal gain.
let initialSpace = MacWindowTracker.currentSpaceId()
activeSpaceId = initialSpace
_ = ensurePanel(forSpace: initialSpace, initialWindows: [])

tracker.onRefreshComplete = { [weak self] spaceId, windows in
    // ... callback implementation ...
}
```

#### Refresh callback (replaces all Combine subscriptions for space/window routing)

```swift
tracker.onRefreshComplete = { [weak self] spaceId, windows in
    guard let self else { return }
    
    // App-Side Scope Enforcement:
    // Filter windows to ensure single-display scope (primary display only).
    // This keeps the WindowTracker library pure and general-purpose.
    // IMPORTANT: Use NSScreen.screens.first (the menu-bar screen, stable) — NOT
    // NSScreen.main, which follows key focus and flips to secondary monitors.
    let primaryScreenFrame = NSScreen.screens.first?.frame ?? .zero
    let filteredWindows = windows.filter { window in
        window.rect.intersects(primaryScreenFrame)
    }

    // CRITICAL: Update activeSpaceId from LIVE CGS value.
    // DECOUPLED STRATEGY:
    // - spaceId (snapshot) drives the CONTENT of the panel for that space.
    // - activeSpaceId (live) drives the INTERACTION (shortcuts, visibility protection) of the app.
    // This allows us to update a background/sliding-out panel (via spaceId) without confusing
    // the app about which space is currently active (via activeSpaceId).
    activeSpaceId = MacWindowTracker.currentSpaceId()

    // Update the snapshot space's panel (may be a background space during rapid switching)
    let isNewPanel = ensurePanel(forSpace: spaceId, initialWindows: filteredWindows)

    // Only update state if ensurePanel didn't just create and populate it
    if !isNewPanel {
        spaceStates[spaceId]?.windows = filteredWindows
    }

    // IMPORTANT: Also ensure the ACTIVE space has a panel. During rapid switching (A→B→C),
    // the snapshot may be for space B while activeSpaceId is already C. If we only create
    // panels for the snapshot space, C's panel won't exist until C's refresh fires — which
    // may not happen until the 2-second safety timer. Eagerly creating it here (with empty
    // windows) ensures the shortcut handler always has a valid state object. The windows
    // will be populated when C's refresh eventually fires.
    if spaceStates[activeSpaceId] == nil {
        _ = ensurePanel(forSpace: activeSpaceId, initialWindows: [])
    }

    keyboardShortcutHandler.currentSpaceState = spaceStates[activeSpaceId] // Use active space
    // Use the ACTIVE space's windows for maximized-window adjustment, not the snapshot's.
    // During rapid switching, the snapshot may be for a background space — adjusting
    // maximized windows based on background-space data would resize the wrong windows.
    let activeWindows = spaceStates[activeSpaceId]?.windows ?? filteredWindows
    adjustMaximizedWindows(activeWindows, tracker: tracker)
    
    // Clean up invalid spaces (deleted by user)
    cleanupInvalidPanels()
}
```

#### Rapid space switching (A→B→C)

When the user switches spaces quickly, multiple `spaceChange` events fire in sequence. Because `RefreshManager.refreshNow` is called for each and `performRefresh` is async, these execute serially on the MainActor (Swift concurrency guarantees FIFO ordering for `@MainActor` tasks). Each callback's `spaceId` snapshot reflects the space at the time that particular refresh ran `CGSGetActiveSpace` — which may lag behind the user's current space.

**This is acceptable** because:
- `ensurePanel(forSpace: spaceId)` is idempotent — creating a panel for space B with B's windows is correct even if the user is now on C.
- `activeSpaceId` is re-read live from `CGSGetActiveSpace()` in each callback, so the keyboard shortcut handler always points at the truly-active space.
- The worst case is a panel for an intermediate space (B) gets created with slightly stale data, which is corrected on the next periodic refresh (2s safety net).

No additional synchronization is needed.

#### Panel creation and space binding

`ensurePanel(forSpace spaceId: Int, initialWindows: [TrackedWindow]) -> Bool`:

Returns `true` if a new panel was created, `false` if one already existed.

1. Guard `panels[spaceId] == nil` — if exists, return `false`. **Do NOT update state here.** The caller is responsible for updating state if the panel already exists (the `!isNewPanel` branch in `onRefreshComplete`).
2. Create `SpaceBarState`:
   ```swift
   let state = SpaceBarState(spaceId: spaceId) { [weak tracker] window in
       // Note: try? intentionally swallows errors. If tracker is nil (replaced/deallocated),
       // activation silently no-ops. For debugging, consider logging failures here.
       try? await tracker?.activateWindow(window)
   }
   state.windows = initialWindows
   ```
3. Create NSPanel with same frame/style as before, but `collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary, .transient]` — NO `.canJoinAllSpaces` and NO `.stationary` (which forces it to all spaces).
   **Why `.transient`:** Without `.stationary`, the panel becomes a regular space-bound window that may appear in Mission Control's window picker, get minimized, or participate in App Exposé. `.transient` tells macOS this is a temporary, auxiliary window that should be hidden in Mission Control and Exposé. Combined with `.ignoresCycle` (skips Cmd+Tab) and the `.statusBar` level, this prevents most unwanted window-management interactions.
4. Set `panel.contentView = NSHostingView(rootView: SuperbarContentView(state: state))`
5. **Standardized Show Sequence (deferred reveal):**
   `orderFrontRegardless()` is known to pull windows to the active space, undoing `CGSMoveWindowToSpace`. The established workaround (used by yabai, Hammerspoon) is to hide the window during ordering and defer the reveal to a subsequent run-loop turn, guaranteeing the window server has processed the space move:
   ```swift
   // 1. Make invisible so orderFront doesn't visually pull to current space
   panel.alphaValue = 0
   // 2. Order front (required for the window to be "live" before move)
   panel.orderFrontRegardless()
   // 3. Pin to target space while invisible
   MacWindowTracker.moveWindowToSpace(panel, spaceId: spaceId)
   // 4. Defer reveal to the NEXT run-loop turn.
   //    CGSMoveWindowToSpace posts an async message to the window server. Neither
   //    CATransaction.flush() (which flushes Core Animation, a separate subsystem)
   //    nor RunLoop.current.run(until: Date()) reliably waits for the window server
   //    to process the space assignment. DispatchQueue.main.async defers to the next
   //    run-loop turn, which in practice is sufficient because the window server
   //    processes its queue before the next main-thread dispatch.
   //    If this still flashes on some macOS version, escalate to DispatchQueue.main
   //    .asyncAfter(deadline: .now() + 0.05) as a timed fallback.
   DispatchQueue.main.async {
       panel.alphaValue = 1
   }
   ```
   **POC must validate this sequence** (see Prerequisite section). If the deferred reveal still produces a flash on the current space during the POC, the timed fallback (`asyncAfter` with 50ms) should be tested. If neither works, the panel-per-space approach may need a fundamentally different ordering strategy (e.g., creating the panel off-screen and moving it into position after the space move).
6. Store in `panels[spaceId]` and `spaceStates[spaceId]`
7. Return `true`

Extract `configurePanelStyle(_:)` helper from existing `createSuperbarPanel`:

```swift
/// Configure an NSPanel with the standard superbar appearance.
/// Reads NSScreen.screens.first for frame positioning (primary display).
private func configurePanelStyle(_ panel: NSPanel) {
    let screen = NSScreen.screens.first ?? NSScreen.main!
    let barFrame = NSRect(
        x: screen.frame.origin.x,
        y: screen.frame.origin.y,
        width: screen.frame.width,
        height: barHeight
    )
    panel.setFrame(barFrame, display: false)
    panel.level = .statusBar
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary, .transient]
}
```

#### screenDidChange

```swift
@objc private func screenDidChange() {
    // Update activeSpaceId from the live CGS value before reset
    activeSpaceId = MacWindowTracker.currentSpaceId()

    // Complete Reset on Display Change
    // Display changes (monitor plug/unplug, resolution change) often invalidate space IDs
    // and change coordinate systems. resetAllPanels destroys all panels and triggers a
    // refresh that recreates them with correct frames, so no pre-reset frame update is needed.
    resetAllPanels()
}
```

### 6. Stale panel cleanup

**File:** `Examples/SuperbarApp/Sources/SuperbarApp.swift`

Replace `cleanupStalePanels()` with `cleanupInvalidPanels()`.

**Strategy:** Use `MacWindowTracker.allSpaceIds()` to get the authoritative list of valid spaces. Remove any panel whose space ID is not in this list. This safely handles space deletion without heuristics or timeouts.

```swift
func cleanupInvalidPanels() {
    let validSpaces = MacWindowTracker.allSpaceIds()

    // If allSpaceIds() returned empty, CGSCopySpaces may have failed or the constant
    // may be wrong on this macOS version. Skip cleanup entirely to avoid destroying
    // all panels. Log for debugging.
    guard !validSpaces.isEmpty else {
        NSLog("[Superbar] cleanupInvalidPanels: allSpaceIds() returned empty, skipping cleanup")
        return
    }

    let validSet = Set(validSpaces)
    let invalidKeys = panels.keys.filter { !validSet.contains($0) }

    for spaceId in invalidKeys {
        panels[spaceId]?.orderOut(nil)
        panels.removeValue(forKey: spaceId)
        spaceStates.removeValue(forKey: spaceId)
    }
}
```

**Display Changes:** We still use `resetAllPanels` on `screenDidChange` because display reconfigurations can invalidate *all* IDs or change coordinate systems, making a full reset safer than a diff.

```swift
func resetAllPanels() {
    // Prevent usage of stale state by the shortcut handler
    keyboardShortcutHandler.currentSpaceState = nil

    // Close all existing panels
    for panel in panels.values {
        panel.orderOut(nil)
    }
    panels.removeAll()
    spaceStates.removeAll()
    
    // Trigger an immediate refresh to rebuild the panel for the current space
    // and let lazy creation handle the others as visited.
    // Note: RefreshManager is owned by WindowTracker, not a singleton.
    // Access via the tracker's refresh method instead.
    Task { await tracker.refresh() }
}
```

### 7. KeyboardShortcutHandler

**File:** `Examples/SuperbarApp/Sources/KeyboardShortcutHandler.swift`

- Add `@MainActor var currentSpaceState: SpaceBarState?` — set by AppDelegate in `onRefreshComplete`
- Change `activateAdjacentWindow` to read `currentSpaceState?.windows`
- **Fallback:** If `currentSpaceState` is nil, simply return.
- **Note (Empty State Gap):** When the user rapidly switches to an unvisited space, `onRefreshComplete` eagerly creates that space's panel with an empty window list (see "Also ensure the ACTIVE space has a panel" in the callback). Shortcuts will find no windows to navigate, but the handler is never nil. The windows populate when that space's refresh fires (typically within one run-loop turn of the space-change notification, not the 2-second timer).

## Focus Lag (Data Flicker)

When switching back to a space, the panel may briefly show the old focus state until the next refresh updates it. This is "State Lag" and is acceptable, as opposed to "Structural Flicker" (the entire bar disappearing). The focus indicator will update within one refresh cycle (< 100ms in practice due to notification trigger).

## Verification / Architecture Notes

1.  **TrackedWindow Stability:** Ensure `TrackedWindow` conforms to `Identifiable` and `Equatable` effectively. The existing implementation in `TrackedWindow.swift` already provides this, ensuring efficient SwiftUI diffing to prevent list thrashing.
2.  **`ensurePanel` Responsibility:** `ensurePanel` is strictly a *creation* method. It populates `SpaceBarState` only when creating a new panel. Updating existing panels is the responsibility of the caller (`onRefreshComplete`).
3.  **Shortcut Handler Safety:** `resetAllPanels` explicitly nullifies `keyboardShortcutHandler.currentSpaceState` to prevent the handler from operating on detached/zombie state objects after a display reset.

## Build & Test

1. `swift build` — library compiles
2. `cd Examples/SuperbarApp && swift build` — app compiles
3. Manual test: launch app — immediate empty bar appears, then fills. No pop-in delay.
4. Manual test: switch spaces — each space shows correct windows during transition.
5. Manual test: keyboard shortcut (Ctrl+Alt+Arrow) works.
6. Manual test: rapid space switching (A→B→C quickly) — shortcuts work on arrival at C without waiting for 2-second timer.
7. Manual test: delete a space — panel is cleaned up on next refresh, no crash.
8. Manual test: click window on sliding-out panel — should attempt activation.
9. Manual test: connect external display — main display panels reset and rebuild.
10. **CGSCopySpaces validation:** On launch, log the output of `MacWindowTracker.allSpaceIds()` and compare against the number of spaces visible in Mission Control. Verify: (a) every user space is included, (b) fullscreen spaces are included, (c) no spurious/dead IDs are present. Test with 2+ spaces and at least one fullscreen app. If the count doesn't match, try constants 5, 2, and 1 and document which is correct for the target macOS version.
11. **Panel show sequence validation:** When creating a panel for a non-active space, verify no flash appears on the current space. This is covered by the POC (Prerequisite section) but must be re-verified after integration.
