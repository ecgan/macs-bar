import SwiftUI

struct WelcomeGuidePlacementStep: View {
    @Binding var barPlacementArea: String
    @Binding var panelLevel: String

    var body: some View {
        HStack(spacing: 34) {
            VStack(alignment: .leading, spacing: 18) {
                WelcomeGuideStepTitle(
                    "Choose where the bar appears",
                    description: "Above the Dock is recommended and makes Macs Bar easy to find."
                )

                Picker("Placement", selection: $barPlacementArea) {
                    Text("Above the Dock").tag(BarPlacementArea.visibleFrame.rawValue)
                    Text("Screen edge").tag(BarPlacementArea.screenFrame.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if barPlacementArea == BarPlacementArea.screenFrame.rawValue {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("When the Dock overlaps")
                            .font(.headline)

                        Picker("Dock overlap", selection: $panelLevel) {
                            Text("Behind Dock").tag(PanelLevel.behindDock.rawValue)
                            Text("In front of Dock").tag(PanelLevel.inFrontOfDock.rawValue)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Text("Placing the bar behind the Dock can obscure it when the Dock contains many apps.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label(
                        "Keeps Macs Bar outside the area occupied by the Dock.",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            WelcomeGuideScreenPreview(
                placementArea: BarPlacementArea(rawValue: barPlacementArea) ?? .visibleFrame,
                panelLevel: PanelLevel(rawValue: panelLevel) ?? .behindDock,
                autoHideEnabled: false
            )
            .frame(width: 300, height: 210)
        }
    }
}
