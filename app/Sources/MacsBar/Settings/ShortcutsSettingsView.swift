import SwiftUI

struct ShortcutsSettingsView: View {
    @EnvironmentObject private var storage: ShortcutStorage

    var body: some View {
        Form {
            ForEach(ShortcutAction.allCases, id: \.self) { action in
                ShortcutRecorderView(
                    action: action,
                    shortcut: binding(for: action)
                )
            }

            HStack {
                Spacer()
                Button("Restore Defaults") {
                    storage.resetToDefaults()
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func binding(for action: ShortcutAction) -> Binding<KeyboardShortcut> {
        Binding(
            get: { storage.shortcut(for: action) },
            set: { storage.setShortcut($0, for: action) }
        )
    }
}
