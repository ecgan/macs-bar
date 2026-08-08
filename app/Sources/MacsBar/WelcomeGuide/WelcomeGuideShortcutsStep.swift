import SwiftUI

struct WelcomeGuideShortcutsStep: View {
    @EnvironmentObject private var shortcutStorage: ShortcutStorage

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            WelcomeGuideStepTitle(
                "Use or customize keyboard shortcuts",
                description: "The defaults work immediately. Click a shortcut to record a different key combination."
            )

            WelcomeGuideCard {
                VStack(spacing: 16) {
                    ForEach(ShortcutAction.allCases, id: \.self) { action in
                        ShortcutRecorderView(
                            action: action,
                            shortcut: shortcutBinding(for: action)
                        )

                        if action != ShortcutAction.allCases.last {
                            Divider()
                        }
                    }
                }
            }

            HStack {
                Text("Press Escape while recording to cancel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Restore Defaults") {
                    shortcutStorage.resetToDefaults()
                }
            }
        }
    }

    private func shortcutBinding(for action: ShortcutAction) -> Binding<KeyboardShortcut> {
        Binding(
            get: { shortcutStorage.shortcut(for: action) },
            set: { shortcutStorage.setShortcut($0, for: action) }
        )
    }
}
