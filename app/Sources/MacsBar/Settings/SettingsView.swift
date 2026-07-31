import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            ShowHideSettingsView()
                .tabItem {
                    Label("Show / Hide", systemImage: "eye")
                }

            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 340)
    }
}
