import SwiftUI

struct ShowHideSettingsView: View {
    @AppStorage(AppSettings.autoHideEnabledKey) private var autoHideEnabled = false
    @AppStorage(AppSettings.autoHideActivationHeightKey)
    private var autoHideActivationHeight = AppSettings.defaultAutoHideActivationHeight
    @AppStorage(AppSettings.showInFrontOfDockKey)
    private var showInFrontOfDock = AppSettings.defaultShowInFrontOfDock
    @AppStorage(AppSettings.barPlacementAreaKey)
    private var barPlacementArea = AppSettings.defaultBarPlacementArea.rawValue

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
                Text("Place Macs Bar within")

                Picker("Place Macs Bar within", selection: $barPlacementArea) {
                    Text("Visible frame").tag(BarPlacementArea.visibleFrame.rawValue)
                    Text("Screen frame").tag(BarPlacementArea.screenFrame.rawValue)
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                Text("Visible frame keeps Macs Bar outside the area occupied by the Dock.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("When overlapping the Dock")

                Picker("When overlapping the Dock", selection: $showInFrontOfDock) {
                    Text("Behind Dock").tag(false)
                    Text("In front of Dock").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                Text("Choose whether Macs Bar or magnified Dock icons appear on top.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
