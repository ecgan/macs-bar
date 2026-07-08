import Combine
import ApplicationServices
import AppKit

@MainActor
public final class AccessibilityPermissionManager: ObservableObject {
    @Published public private(set) var isPermissionGranted: Bool = false
    private var pollTask: Task<Void, Never>?

    public init() {
        checkStatus()
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
        checkStatus()
        if isPermissionGranted { return }

        pollTask = Task { [weak self] in
            while true {
                if Task.isCancelled { break }
                do {
                    try await Task.sleep(for: .seconds(1.0))
                } catch {
                    break
                }
                
                let trusted = AXIsProcessTrusted()
                if trusted {
                    self?.isPermissionGranted = true
                    break
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
