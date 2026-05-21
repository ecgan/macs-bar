import CoreGraphics

enum MaximizedWindowCascadeAdjuster {
    static func adjustedFrame(
        for windowFrame: CGRect,
        monitorFrame: CGRect,
        visibleFrame: CGRect,
        barHeight: CGFloat,
        tolerance: CGFloat = 2
    ) -> CGRect? {
        let safeFrame = CGRect(
            x: monitorFrame.minX,
            y: visibleFrame.minY,
            width: monitorFrame.width,
            height: monitorFrame.height - visibleFrame.minY - barHeight
        )

        guard safeFrame.width > 0, safeFrame.height > 0 else { return nil }

        let widthMatchesMonitor = abs(windowFrame.width - monitorFrame.width) <= tolerance
        let heightMatchesVisible = abs(windowFrame.height - visibleFrame.height) <= tolerance
        if widthMatchesMonitor && heightMatchesVisible {
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
