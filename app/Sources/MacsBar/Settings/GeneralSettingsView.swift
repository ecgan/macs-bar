import SwiftUI
import ServiceManagement
import Sparkle

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage(AppSettings.autoHideEnabledKey) private var autoHideEnabled = false
    @AppStorage(AppSettings.autoHideActivationHeightKey)
    private var autoHideActivationHeight = AppSettings.defaultAutoHideActivationHeight
    @EnvironmentObject private var updaterService: UpdaterService

    private var automaticallyChecksForUpdates: Binding<Bool> {
        Binding(
            get: { updaterService.updater.automaticallyChecksForUpdates },
            set: { updaterService.updater.automaticallyChecksForUpdates = $0 }
        )
    }

    var body: some View {
        Form {
            Toggle(isOn: $autoHideEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatically hide and show Macs Bar")
                    Text("Reveal Macs Bar when the pointer reaches the bottom edge of the screen")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if autoHideEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Activation area")
                        Spacer()
                        Text("\(Int(autoHideActivationHeight)) pt")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }

                    Slider(
                        value: $autoHideActivationHeight,
                        in: AppSettings.autoHideActivationHeightRange,
                        step: 1
                    )

                    Text("Distance from the bottom edge that reveals Macs Bar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Toggle(isOn: $launchAtLogin) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at login")
                    Text("Automatically start Macs Bar when you log in to your Mac")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .onChange(of: launchAtLogin) {
                updateLaunchAtLogin(enabled: launchAtLogin)
            }

            Toggle(isOn: automaticallyChecksForUpdates) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Check for updates automatically")
                    Text("Periodically check for new versions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Button("Check for Updates Now...") {
                updaterService.checkForUpdates()
            }
            .disabled(!updaterService.canCheckForUpdates)
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
