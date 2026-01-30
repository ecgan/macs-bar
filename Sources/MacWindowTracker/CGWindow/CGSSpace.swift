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
