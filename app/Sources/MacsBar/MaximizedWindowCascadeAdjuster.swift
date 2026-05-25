import CoreGraphics

enum MaximizedWindowCascadeAdjuster {
    static func adjustedFrame(
        for windowFrame: CGRect,
        monitorFrame: CGRect,
        visibleFrame: CGRect,
        barHeight: CGFloat,
        tolerance: CGFloat = 2
    ) -> CGRect? {
        // Safe frame is the visible area minus the Macs Bar height at the bottom
        let safeFrame = CGRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: visibleFrame.width,
            height: visibleFrame.height - barHeight
        )

        guard safeFrame.width > 0, safeFrame.height > 0 else { return nil }

        // Determine if the window is maximized to fill the screen (with some tolerance).
        // A window is maximized if its width is close to the monitor or visible width,
        // and its height is close to the visible height, the full monitor height, or
        // the monitor height minus the top menu bar.
        let widthMatchesMonitor = abs(windowFrame.width - monitorFrame.width) <= tolerance
        let widthMatchesVisible = abs(windowFrame.width - visibleFrame.width) <= tolerance
        let widthMatches = widthMatchesMonitor || widthMatchesVisible

        let heightMatchesVisible = abs(windowFrame.height - visibleFrame.height) <= tolerance
        let heightMatchesMonitor = abs(windowFrame.height - monitorFrame.height) <= tolerance
        let heightMatchesFullUsable = abs(windowFrame.height - (monitorFrame.height - visibleFrame.minY)) <= tolerance
        let heightMatches = heightMatchesVisible || heightMatchesMonitor || heightMatchesFullUsable

        if widthMatches && heightMatches {
            return safeFrame
        }

        let cascadeInsetLimit: CGFloat = 80
        let deltaX = windowFrame.minX - safeFrame.minX
        let deltaY = windowFrame.minY - safeFrame.minY
        let widthNearSafe = windowFrame.width >= safeFrame.width - cascadeInsetLimit
            && windowFrame.width <= safeFrame.width + tolerance
        let heightNearSafe = windowFrame.height >= safeFrame.height - cascadeInsetLimit
            && windowFrame.height <= safeFrame.height + tolerance

        let isCascadedFromSafeWindow = deltaX >= -tolerance
            && deltaX <= cascadeInsetLimit
            && deltaY > tolerance
            && deltaY <= cascadeInsetLimit
            && widthNearSafe
            && heightNearSafe

        return isCascadedFromSafeWindow ? safeFrame : nil
    }
}
