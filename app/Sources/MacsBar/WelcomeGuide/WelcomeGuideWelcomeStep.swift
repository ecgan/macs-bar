import SwiftUI

struct WelcomeGuideWelcomeStep: View {
    var body: some View {
        VStack(spacing: 22) {
            Text("A taskbar for the windows in your current desktop Space")
                .font(.system(size: 25, weight: .semibold))
                .multilineTextAlignment(.center)

            Text("Macs Bar keeps your open windows visible at the bottom of the screen so you can switch between them with a click or a keyboard shortcut.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 540)

            WelcomeGuideScreenPreview(
                placementArea: .visibleFrame,
                panelLevel: .behindDock,
                autoHideEnabled: false
            )
            .frame(width: 430, height: 190)

            Label(
                "Look for the Macs Bar icon in the menu bar whenever you need Settings or want to quit.",
                systemImage: "menubar.rectangle"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}
