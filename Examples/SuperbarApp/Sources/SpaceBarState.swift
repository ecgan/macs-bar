import Combine
import MacWindowTracker

@MainActor
class SpaceBarState: ObservableObject {
    let spaceId: Int
    @Published var windows: [TrackedWindow] = []
    private let onActivate: (TrackedWindow) async -> Void

    init(spaceId: Int, onActivate: @escaping @MainActor (TrackedWindow) async -> Void) {
        self.spaceId = spaceId
        self.onActivate = onActivate
    }

    func activateWindow(_ window: TrackedWindow) async {
        await onActivate(window)
    }
}
