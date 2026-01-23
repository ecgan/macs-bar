import SwiftUI
import MacWindowTracker

struct SuperbarContentView: View {
    @ObservedObject var tracker: WindowTracker

    var body: some View {
        HStack(spacing: 4) {
            Spacer()

            ForEach(tracker.windows) { window in
                SuperbarItem(window: window, tracker: tracker)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SuperbarItem: View {
    let window: TrackedWindow
    let tracker: WindowTracker

    var body: some View {
        Button(action: activateWindow) {
            HStack(spacing: 6) {
                AppIcon(bundleId: window.appBundleId)
                    .frame(width: 20, height: 20)

                Text(window.title ?? window.appName)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: 180)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(window.isFocused
                        ? Color.white.opacity(0.2)
                        : Color.white.opacity(0.05))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func activateWindow() {
        Task {
            do {
                try await tracker.activateWindow(window)
            } catch {
                print("Failed to activate window: \(error)")
            }
        }
    }
}

struct AppIcon: View {
    let bundleId: String?

    var body: some View {
        if let bundleId,
           let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let icon = NSWorkspace.shared.icon(forFile: appUrl.path)
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.gray)
        }
    }
}
