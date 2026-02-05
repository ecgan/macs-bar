import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("checkForUpdatesAutomatically") private var checkForUpdates = true

    var body: some View {
        Form {
            Toggle(isOn: $launchAtLogin) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at login")
                    Text("Automatically start Macs Bar when you log in to your Mac")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .onChange(of: launchAtLogin) { newValue in
                updateLaunchAtLogin(enabled: newValue)
            }

            Toggle(isOn: $checkForUpdates) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Check for updates automatically")
                    Text("Periodically check for new versions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            syncLaunchAtLoginState()
        }
    }

    private func syncLaunchAtLoginState() {
        let status = SMAppService.mainApp.status
        launchAtLogin = (status == .enabled)
    }

    private func updateLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
            // Revert UI state on failure
            syncLaunchAtLoginState()
        }
    }
}
