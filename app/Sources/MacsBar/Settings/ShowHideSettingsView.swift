import SwiftUI

struct ShowHideSettingsView: View {
    @AppStorage(AppSettings.autoHideEnabledKey) private var autoHideEnabled = false
    @AppStorage(AppSettings.autoHideActivationHeightKey)
    private var autoHideActivationHeight = AppSettings.defaultAutoHideActivationHeight
    @AppStorage(AppSettings.showInFrontOfDockKey)
    private var showInFrontOfDock = AppSettings.defaultShowInFrontOfDock

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $autoHideEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatically hide and show Macs Bar")
                    Text("Reveal Macs Bar when the pointer reaches the bottom edge of the screen")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

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
            .disabled(!autoHideEnabled)
            .padding(.leading, 22)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("When overlapping the Dock")

                Picker("When overlapping the Dock", selection: $showInFrontOfDock) {
                    Text("Behind Dock").tag(false)
                    Text("In front of Dock").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                Text("Choose whether Macs Bar or the Dock appears on top.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
