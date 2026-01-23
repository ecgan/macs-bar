import ApplicationServices
import CoreGraphics

/// Helper extensions for working with AXUIElement
extension AXUIElement {
    /// Create an AXUIElement for an application by PID
    static func application(pid: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    /// Get the focused window of this application element
    func focusedWindow() -> (windowId: CGWindowID, element: AXUIElement)? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, kAXFocusedWindowAttribute as CFString, &value)
        guard result == .success, let windowElement = value else { return nil }

        // Get the window ID using private API
        var windowId: CGWindowID = 0
        let idResult = _AXUIElementGetWindow(windowElement as! AXUIElement, &windowId)
        guard idResult == .success else { return nil }

        return (windowId, windowElement as! AXUIElement)
    }

    /// Get the window ID for this element (if it's a window)
    func windowId() -> CGWindowID? {
        var windowId: CGWindowID = 0
        let result = _AXUIElementGetWindow(self, &windowId)
        return result == .success ? windowId : nil
    }

    /// Get a string attribute value
    func stringAttribute(_ attribute: String) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    /// Get a boolean attribute value
    func boolAttribute(_ attribute: String) -> Bool? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? Bool
    }

    /// Get the title of this element
    var title: String? {
        stringAttribute(kAXTitleAttribute)
    }

    /// Check if this element is the main window
    var isMain: Bool {
        boolAttribute(kAXMainAttribute) ?? false
    }

    /// Raise this window to front
    @discardableResult
    func raise() -> Bool {
        AXUIElementPerformAction(self, kAXRaiseAction as CFString) == .success
    }

    /// Set this as the main window
    @discardableResult
    func setMain(_ value: Bool) -> Bool {
        AXUIElementSetAttributeValue(self, kAXMainAttribute as CFString, value as CFTypeRef) == .success
    }

    /// Set the size of this window
    @discardableResult
    func setSize(_ size: CGSize) -> Bool {
        var cfSize = size
        guard let value = AXValueCreate(.cgSize, &cfSize) else { return false }
        return AXUIElementSetAttributeValue(self, kAXSizeAttribute as CFString, value) == .success
    }
}

// MARK: - Private API Declaration

/// Private API to get CGWindowID from AXUIElement
/// This is the same API used by AeroSpace
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowId: UnsafeMutablePointer<CGWindowID>) -> AXError
