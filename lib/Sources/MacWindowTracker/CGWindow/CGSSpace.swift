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

private typealias CGSCopyManagedDisplaySpacesFn = @convention(c) (Int32) -> CFArray?
private let _CGSCopyManagedDisplaySpaces: CGSCopyManagedDisplaySpacesFn? = {
    guard let skylight, let sym = dlsym(skylight, "CGSCopyManagedDisplaySpaces") else { return nil }
    return unsafeBitCast(sym, to: CGSCopyManagedDisplaySpacesFn.self)
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

/// Check if a space is a fullscreen space.
public func isFullScreenSpace(_ spaceId: Int) -> Bool {
    // Space type 4 = fullscreen spaces only
    guard let copySpaces = _CGSCopySpaces,
          let fullscreenSpaces = copySpaces(CGSMainConnectionID(), 4) as? [Int] else { return false }
    return fullscreenSpaces.contains(spaceId)
}

/// Check if displays share a single space ("Displays have separate Spaces" is OFF in System Settings).
/// When true, all displays show the same space and windows from all displays should be shown together.
public func displaysShareSpace() -> Bool {
    // spans-displays: 1 = spaces span across displays (separate spaces OFF)
    //                 0 or missing = each display has its own spaces (separate spaces ON)
    return UserDefaults(suiteName: "com.apple.spaces")?.bool(forKey: "spans-displays") ?? false
}

/// Returns current space IDs for each display.
/// Key: display UUID, Value: array of space IDs (first is current/active space for that display)
/// Returns empty dictionary if API fails or displays share spaces.
public func spacesPerDisplay() -> [String: [Int]] {
    guard let copyManagedDisplaySpaces = _CGSCopyManagedDisplaySpaces,
          let displays = copyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]] else {
        return [:]
    }

    var result: [String: [Int]] = [:]
    for display in displays {
        guard let uuid = display["Display Identifier"] as? String else { continue }

        var spaceIds: [Int] = []

        // Add current space first (it's the active space for this display)
        if let currentSpace = display["Current Space"] as? [String: Any],
           let currentId = currentSpace["id64"] as? Int {
            spaceIds.append(currentId)
        }

        // Add remaining spaces (excluding current to avoid duplicates)
        if let spaces = display["Spaces"] as? [[String: Any]] {
            for space in spaces {
                if let spaceId = space["id64"] as? Int, !spaceIds.contains(spaceId) {
                    spaceIds.append(spaceId)
                }
            }
        }

        if !spaceIds.isEmpty {
            result[uuid] = spaceIds
        }
    }

    return result
}

/// Get the display UUID for an NSScreen.
/// Returns nil if the screen number can't be converted to a UUID.
public func displayUUID(for screen: NSScreen) -> String? {
    guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
        return nil
    }
    guard let uuid = CGDisplayCreateUUIDFromDisplayID(screenNumber)?.takeRetainedValue() else {
        return nil
    }
    return CFUUIDCreateString(nil, uuid) as String?
}
