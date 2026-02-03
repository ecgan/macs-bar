import AppKit
import CoreGraphics

/// Private CoreGraphics API to get the active Space ID.
/// Used by window managers (yabai, AeroSpace) — stable across macOS versions.
@_silgen_name("CGSGetActiveSpace")
func CGSGetActiveSpace(_ connection: Int32) -> Int

/// Private CoreGraphics API to get the default connection.
@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> Int32

// CGSMoveWindowToSpace and CGSCopySpaces are loaded at runtime via dlsym
// because they live in SkyLight.framework (private) and aren't auto-linked.
nonisolated(unsafe) private let skylight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

private typealias CGSMoveWindowToSpaceFn = @convention(c) (Int32, UInt32, Int) -> Void
private let _CGSMoveWindowToSpace: CGSMoveWindowToSpaceFn? = {
    guard let skylight, let sym = dlsym(skylight, "CGSMoveWindowToSpace") else { return nil }
    return unsafeBitCast(sym, to: CGSMoveWindowToSpaceFn.self)
}()

private typealias CGSCopySpacesFn = @convention(c) (Int32, Int32) -> CFArray?
private let _CGSCopySpaces: CGSCopySpacesFn? = {
    guard let skylight, let sym = dlsym(skylight, "CGSCopySpaces") else { return nil }
    return unsafeBitCast(sym, to: CGSCopySpacesFn.self)
}()

/// Get the current macOS Space ID.
public func currentSpaceId() -> Int {
    CGSGetActiveSpace(CGSMainConnectionID())
}

/// Move an NSWindow to a specific space.
@MainActor public func moveWindowToSpace(_ window: NSWindow, spaceId: Int) {
    _CGSMoveWindowToSpace?(CGSMainConnectionID(), UInt32(window.windowNumber), spaceId)
}

/// Get the list of all valid space IDs.
/// Returns empty array if CGSCopySpaces fails — caller must treat empty as "unknown"
/// and skip cleanup entirely.
public func allSpaceIds() -> [Int] {
    // Space type 7 = user + fullscreen spaces
    guard let copySpaces = _CGSCopySpaces,
          let spaces = copySpaces(CGSMainConnectionID(), 7) as? [Int],
          !spaces.isEmpty else { return [] }
    return spaces
}
