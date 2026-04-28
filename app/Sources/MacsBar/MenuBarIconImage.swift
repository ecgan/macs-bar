import AppKit

enum MenuBarIconImage {
    static let taskbarTemplate: NSImage = {
        let size = NSSize(width: 18, height: 14)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.black.setStroke()
        NSColor.black.setFill()

        let screenRect = NSRect(x: 1.6, y: 1.8, width: 14.8, height: 10.2)
        let screenPath = NSBezierPath(roundedRect: screenRect, xRadius: 2.0, yRadius: 2.0)
        screenPath.lineWidth = 1.0
        screenPath.stroke()

        let taskbarRect = NSRect(x: 2.3, y: 2.5, width: 13.4, height: 4.7)
        let taskbarPath = NSBezierPath(roundedRect: taskbarRect, xRadius: 1.4, yRadius: 1.4)
        taskbarPath.fill()

        let activeSlotRect = NSRect(x: 4.2, y: 3.9, width: 4.9, height: 2.15)
        let inactiveSlotRect = NSRect(x: 10.15, y: 3.9, width: 2.2, height: 2.15)

        NSColor.white.setFill()
        NSBezierPath(roundedRect: activeSlotRect, xRadius: 0.75, yRadius: 0.75).fill()

        NSColor.white.withAlphaComponent(0.5).setFill()
        NSBezierPath(roundedRect: inactiveSlotRect, xRadius: 0.75, yRadius: 0.75).fill()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }()
}
