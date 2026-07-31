import AppKit

enum BarPlacementArea: String {
    case screenFrame
    case visibleFrame
}

struct PanelScreenGeometry: Equatable {
    let screenFrame: NSRect
    let visibleFrame: NSRect
}

enum PanelPlacementPolicy {
    static func placementFrame(
        for geometry: PanelScreenGeometry,
        area: BarPlacementArea
    ) -> NSRect {
        switch area {
        case .screenFrame:
            geometry.screenFrame
        case .visibleFrame:
            geometry.visibleFrame
        }
    }

    static func barFrame(
        for geometry: PanelScreenGeometry,
        area: BarPlacementArea,
        barHeight: CGFloat
    ) -> NSRect {
        let placementFrame = placementFrame(for: geometry, area: area)
        return NSRect(
            x: placementFrame.minX,
            y: placementFrame.minY,
            width: placementFrame.width,
            height: barHeight
        )
    }
}
