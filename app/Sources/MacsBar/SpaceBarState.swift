import Combine
import MacWindowTracker
import CoreGraphics

@MainActor
class SpaceBarState: ObservableObject {
    let spaceId: Int
    @Published var windows: [TrackedWindow] = []
    @Published var pillWidth: CGFloat = 0
    private let onActivate: (TrackedWindow) async -> Void
    private let onClose: (TrackedWindow) -> Void

    init(
        spaceId: Int,
        onActivate: @escaping @MainActor (TrackedWindow) async -> Void,
        onClose: @escaping @MainActor (TrackedWindow) -> Void
    ) {
        self.spaceId = spaceId
        self.onActivate = onActivate
        self.onClose = onClose
    }

    func activateWindow(_ window: TrackedWindow) async {
        await onActivate(window)
    }

    func closeWindow(_ window: TrackedWindow) {
        onClose(window)
    }
}
