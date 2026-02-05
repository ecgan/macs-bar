import SwiftUI

struct AboutView: View {
    private let githubURL = URL(string: "https://github.com/ecgan/macs-bar")!
    private let websiteURL = URL(string: "https://example.com")! // Placeholder

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // App Icon
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 64, height: 64)
            }

            // App Name
            Text("Macs Bar")
                .font(.title)
                .fontWeight(.semibold)

            // Version
            Text("Version \(appVersion)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Copyright
            Text("© 2024 Your Name. All rights reserved.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Links
            HStack(spacing: 16) {
                Button("GitHub") {
                    NSWorkspace.shared.open(githubURL)
                }
                .buttonStyle(.link)

                Button("Website") {
                    NSWorkspace.shared.open(websiteURL)
                }
                .buttonStyle(.link)
            }
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}
