import Combine
import Foundation
import Sparkle

@MainActor
final class UpdaterService: ObservableObject {
    private let updaterController: SPUStandardUpdaterController
    private var cancellable: AnyCancellable?

    @Published var canCheckForUpdates = false

    var updater: SPUUpdater {
        updaterController.updater
    }

    init() {
        // Only start the updater when running from a proper .app bundle.
        // `swift run` runs the bare executable without bundle structure,
        // causing Sparkle to fail with an error dialog.
        let isAppBundle = Bundle.main.bundleURL.pathExtension == "app"
        updaterController = SPUStandardUpdaterController(
            startingUpdater: isAppBundle,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        cancellable = updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: \.canCheckForUpdates, on: self)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
