import SwiftUI

struct WelcomeGuideAccessibilityStep: View {
    @EnvironmentObject private var permissionManager: AccessibilityPermissionManager

    var body: some View {
        VStack(spacing: 22) {
            WelcomeGuideStepTitle(
                "Allow Accessibility access",
                description: "Macs Bar needs this permission to discover open windows, keep the bar updated, activate windows, and listen for global keyboard shortcuts."
            )

            WelcomeGuideCard {
                HStack(spacing: 14) {
                    Image(systemName: permissionManager.isPermissionGranted
                          ? "checkmark.circle.fill"
                          : "exclamationmark.triangle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(permissionManager.isPermissionGranted ? .green : .orange)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(permissionManager.isPermissionGranted
                             ? "Accessibility access is enabled"
                             : "Accessibility access is not enabled")
                            .font(.headline)
                        Text(permissionManager.isPermissionGranted
                             ? "Macs Bar can now start tracking your windows."
                             : "You can continue without it, but Macs Bar will not operate until access is enabled.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            if !permissionManager.isPermissionGranted {
                HStack(spacing: 12) {
                    Button("Request Accessibility Access") {
                        permissionManager.promptUserForPermission()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Open System Settings") {
                        permissionManager.openSystemSettings()
                    }
                }
            }

            Text("The status above updates automatically after you enable Macs Bar in System Settings → Privacy & Security → Accessibility.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
        }
    }
}
