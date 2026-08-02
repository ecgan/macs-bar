import SwiftUI

struct ShowHideSettingsView: View {
    @AppStorage(AppSettings.autoHideEnabledKey) private var autoHideEnabled = false
    @AppStorage(AppSettings.autoHideActivationHeightKey)
    private var autoHideActivationHeight = AppSettings.defaultAutoHideActivationHeight
    @AppStorage(AppSettings.panelLevelKey)
    private var panelLevel = AppSettings.defaultPanelLevel.rawValue
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

                Text("Visible frame keeps Macs Bar within the area not covered by the Dock or menu bar.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Screen frame keeps Macs Bar within the entire screen area.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("When overlapping the Dock")

                Picker("When overlapping the Dock", selection: $panelLevel) {
                    Text("Behind Dock").tag(PanelLevel.behindDock.rawValue)
                    Text("In front of Dock").tag(PanelLevel.inFrontOfDock.rawValue)
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                Text("Choose whether Macs Bar should appear behind or in front of the Dock when overlapping.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
