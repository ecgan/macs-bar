import SwiftUI

struct WelcomeGuideReadyStep: View {
    @EnvironmentObject private var permissionManager: AccessibilityPermissionManager

    let barPlacementArea: String
    let autoHideEnabled: Bool

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            WelcomeGuideStepTitle(
                "Macs Bar is ready",
                description: "Open a few application windows and look near the bottom of the screen. Click an item in Macs Bar or use your shortcuts to switch windows."
            )

            WelcomeGuideCard {
                VStack(alignment: .leading, spacing: 13) {
                    readinessRow(
                        icon: permissionManager.isPermissionGranted
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill",
                        color: permissionManager.isPermissionGranted ? .green : .orange,
                        title: permissionManager.isPermissionGranted
                            ? "Accessibility enabled"
                            : "Accessibility still needs to be enabled"
                    )
                    readinessRow(
                        icon: "rectangle.bottomthird.inset.filled",
                        color: .accentColor,
                        title: barPlacementArea == BarPlacementArea.visibleFrame.rawValue
                            ? "Placed above the Dock"
                            : "Placed at the screen edge"
                    )
                    readinessRow(
                        icon: autoHideEnabled ? "eye.slash" : "eye",
                        color: .accentColor,
                        title: autoHideEnabled ? "Automatically hides" : "Always visible"
                    )
                }
            }

            Text("You can reopen this guide from the Macs Bar menu or Settings → General.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func readinessRow(
        icon: String,
        color: Color,
        title: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(title)
        }
    }
}
