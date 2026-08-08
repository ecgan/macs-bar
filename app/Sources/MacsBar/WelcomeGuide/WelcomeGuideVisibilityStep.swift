import SwiftUI

struct WelcomeGuideVisibilityStep: View {
    @Binding var autoHideEnabled: Bool
    @Binding var autoHideActivationHeight: Double
    let barPlacementArea: String
    let panelLevel: String

    var body: some View {
        HStack(spacing: 34) {
            VStack(alignment: .leading, spacing: 20) {
                WelcomeGuideStepTitle(
                    "Keep it visible or reveal it when needed",
                    description: "Macs Bar is always visible by default. Auto-hide reveals it when the pointer reaches the bottom edge."
                )

                Toggle("Automatically hide and show Macs Bar", isOn: $autoHideEnabled)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Activation area")
                        Spacer()
                        Text("\(Int(autoHideActivationHeight)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(
                        value: $autoHideActivationHeight,
                        in: AppSettings.autoHideActivationHeightRange,
                        step: 1
                    )

                    Text("A larger area makes the hidden bar easier to reveal.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!autoHideEnabled)
                .opacity(autoHideEnabled ? 1 : 0.55)

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            WelcomeGuideScreenPreview(
                placementArea: BarPlacementArea(rawValue: barPlacementArea) ?? .visibleFrame,
                panelLevel: PanelLevel(rawValue: panelLevel) ?? .behindDock,
                autoHideEnabled: autoHideEnabled
            )
            .frame(width: 300, height: 210)
        }
    }
}
