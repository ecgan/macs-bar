import Combine
import ApplicationServices
import AppKit

@MainActor
public final class AccessibilityPermissionManager: ObservableObject {
    @Published public private(set) var isPermissionGranted: Bool = false
    // `nonisolated(unsafe)` allows deinit (which cannot be @MainActor-isolated) to cancel
    // the task. All other access happens on the main actor, so there is no data race.
    nonisolated(unsafe) private var pollTask: Task<Void, Never>?

    public init() {
        checkStatus()
        startPolling()
    }

    deinit {
        pollTask?.cancel()
    }

    public func checkStatus() {
        let trusted = AXIsProcessTrusted()
        if trusted != isPermissionGranted {
            isPermissionGranted = trusted
        }
    }

    public func requestPermission() {
        // Trigger system prompt
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        
        // Start polling if not granted
        startPolling()
    }

    public func startPolling() {
        guard pollTask == nil else { return }

        pollTask = Task { [weak self] in
            while true {
                if Task.isCancelled { break }
                do {
                    try await Task.sleep(for: .seconds(1.0))
                } catch {
                    break
                }
                
                let trusted = AXIsProcessTrusted()
                if let self {
                    if self.isPermissionGranted != trusted {
                        self.isPermissionGranted = trusted
                    }
                }
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    public func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
