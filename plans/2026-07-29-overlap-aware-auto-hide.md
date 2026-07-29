# Overlap-Aware Auto-Hide for Macs Bar

## Problem statement

Macs Bar is displayed as an always-on-top floating pill at the bottom of the screen. Keeping the window list visible is useful, but the pill can cover the bottom content and controls of zoomed or otherwise large windows. This is especially noticeable on smaller displays, such as a 16-inch MacBook Pro screen.

An earlier approach attempted to reserve space for Macs Bar by reducing the height of maximized windows. That approach caused an undesirable window cascading problem:

1. The user maximizes a window, such as Google Chrome.
2. Macs Bar reduces the window height so that it ends above the bar.
3. The user creates another window in the same application.
4. The application gives the new window approximately the same dimensions as the adjusted window, while macOS places it slightly lower as part of its normal cascading behavior.
5. The new window's bottom content and resize edge end up behind Macs Bar.

Macs Bar can attempt to detect and reposition these cascaded windows, but this turns the app into a partial window manager. Reactive corrections may cause visible window jumps, can misidentify intentionally positioned windows, and may conflict with applications that manage their own window geometry.

The underlying limitation is that macOS does not consider a third-party floating panel to be reserved screen space. Adjusting one window does not change the system's usable screen frame or the placement rules applied to future windows.

## Suggested solution

Introduce an **overlap-aware auto-hide mode**. Instead of resizing user windows, Macs Bar temporarily collapses when the focused window overlaps the area normally occupied by the expanded pill.

When collapsed, Macs Bar displays a small reveal handle near the bottom center of the screen. Hovering over the handle temporarily reveals the full pill.

## MVP scope

The first implementation includes:

- Two visibility modes:
  - **Overlap-aware auto-hide** — recommended default
  - **Always visible** — preserves the current overlay behavior except during fullscreen suppression
- Overlap detection using the globally focused window.
- Evaluation only for panels Macs Bar already creates.
- A small bottom-center reveal handle while collapsed.
- Hover-to-reveal behavior.
- A short delay before collapsing after the pointer leaves.
- Existing native and application-controlled fullscreen suppression.
- Independent visibility state for each existing panel.
- No resizing or repositioning of application windows.

When displays share a Space, Macs Bar continues to create only one panel on the primary display. Creating panels on every display is outside the scope of this issue.

## Visibility rules

Apply these rules in priority order:

1. If the panel is suppressed by existing fullscreen detection, hide both the pill and reveal handle.
2. If the visibility mode is **Always visible**, show the expanded pill.
3. If focused-window information is temporarily unavailable, retain the most recent stable state for a short grace period.
4. If there is no focused application window after the grace period, show the expanded pill.
5. If the focused window does not overlap the canonical expanded pill frame, show the expanded pill.
6. If the focused window overlaps the canonical expanded pill frame and the pointer is over the handle or pill, temporarily show the expanded pill.
7. Otherwise, show only the collapsed reveal handle.
8. After the pointer leaves a temporarily revealed pill, wait for a short fixed delay before collapsing it again.

The initial implementation should use internal timing constants rather than exposing timing preferences.

## Overlap detection

Overlap must always be calculated against the **canonical expanded pill frame**, even while the pill is collapsed or animating.

The canonical frame is the area the fully expanded pill would occupy:

- horizontally centered on its display;
- using the most recent nonzero measured pill width; and
- using the pill's normal 32-point height.

Do not calculate overlap against the collapsed handle. Changing the overlap target based on the current visibility state could cause repeated expand/collapse oscillation.

Do not use the full-width transparent panel as the overlap target. A window that reaches the bottom of the screen but does not extend behind the centered pill should not cause the pill to collapse.

The overlap calculation should:

- use the focused tracked window's current frame;
- convert panel and window geometry into the same coordinate system;
- allow a small tolerance for frame rounding;
- update after focus, move, resize, Space, and display changes; and
- ignore Macs Bar's own panels and Settings window.

macOS has one globally focused window rather than one focused window per display. Therefore, only an existing panel whose canonical frame intersects that focused window will collapse.

## Interaction and animation

- Collapse and reveal animations must not move or resize application windows.
- The reveal handle should be visually subtle but discoverable. A height of approximately 3–5 points is a reasonable starting point.
- The handle may have a slightly larger interaction target, but only that defined target may intercept pointer events while collapsed.
- The rest of the transparent panel must remain click-through.
- Revealing the pill must provide enough time for the pointer to move from the handle into the pill.
- The pill must remain visible while the pointer is interacting with it.
- Context menus and window activation must continue to work normally while revealed.
- Visibility must not oscillate during window or pill animations.

## Dock behavior

The MVP does not attempt to control, suppress, or reposition the macOS Dock.

The interaction must be tested manually with the Dock:

- visible at the bottom;
- auto-hidden at the bottom;
- positioned on the left; and
- positioned on the right.

In particular, verify whether approaching the reveal handle also reveals an auto-hidden bottom Dock. If that interaction makes Macs Bar difficult to use, adjust the handle position or activation area before making overlap-aware mode the default.

## Acceptance criteria

- Macs Bar does not resize or reposition application windows.
- The expanded pill remains visible when the focused window does not overlap its canonical frame.
- The pill collapses when the focused window overlaps its canonical frame.
- Overlap continues to use the expanded pill frame while collapsed.
- The visibility state does not oscillate after collapsing.
- Hovering over the reveal handle reliably reveals the full pill.
- The pill remains visible while the pointer is interacting with it.
- The pill collapses shortly after the pointer leaves if overlap still exists.
- Only the reveal handle's interaction target receives pointer events while collapsed.
- Clicking the desktop or otherwise reaching a stable no-focused-window state shows the expanded pill.
- Existing fullscreen detection hides both the pill and reveal handle.
- Each existing panel maintains its own visibility state.
- Shared-Spaces mode continues to show one panel on the primary display.
- Opening a cascaded Chrome window does not cause Macs Bar to alter the window's frame.
- Space switching, focus changes, window resizing, and animations do not produce noticeable flicker.

## Out of scope

- Resizing or repositioning application windows.
- Reserving system-wide usable screen space.
- Creating a panel on every display when displays share a Space.
- A global show/hide shortcut.
- Briefly showing Macs Bar after the focused window changes.
- User-configurable reveal or collapse delays.
- Dock-specific control or integration.
- Per-application visibility rules.
- Vertical or side-mounted bars.

## Possible follow-up issues

- Add a configurable global reveal shortcut.
- Briefly reveal Macs Bar after the focused window changes.
- Add timing preferences if the fixed delays do not work well for most users.
- Add panels to every display when displays share a Space.
- Improve behavior when Macs Bar and an auto-hidden bottom Dock reveal simultaneously.
