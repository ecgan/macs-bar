import AppKit

enum MenuBarIconImage {
    static let taskbarTemplate: NSImage = {
        let size = NSSize(width: 18, height: 14)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.black.setStroke()
        NSColor.black.setFill()

        let screenRect = NSRect(x: 1.25, y: 1.5, width: 15.5, height: 11.0)
        let screenPath = NSBezierPath(roundedRect: screenRect, xRadius: 2, yRadius: 2)
        screenPath.lineWidth = 1
        screenPath.stroke()

        let taskbarRect = NSRect(x: 2.7, y: 2.8, width: 12.6, height: 3.6)
        let taskbarPath = NSBezierPath(roundedRect: taskbarRect, xRadius: 1.1, yRadius: 1.1)
        taskbarPath.fill()

        let slotRects = [
            NSRect(x: 4.0, y: 3.65, width: 1.7, height: 1.7),
            NSRect(x: 6.35, y: 3.65, width: 1.7, height: 1.7),
            NSRect(x: 8.7, y: 3.65, width: 1.7, height: 1.7),
        ]

        NSColor.white.setFill()
        for rect in slotRects {
            NSBezierPath(roundedRect: rect, xRadius: 0.45, yRadius: 0.45).fill()
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }()
}
