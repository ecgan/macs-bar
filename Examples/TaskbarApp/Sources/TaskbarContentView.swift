import SwiftUI
import MacWindowTracker

struct TaskbarContentView: View {
    @ObservedObject var tracker: WindowTracker
    @State private var selectedMonitor: TrackedMonitor?

    var body: some View {
        VStack(spacing: 0) {
            // Monitor selector
            if tracker.monitors.count > 1 {
                MonitorSelector(
                    monitors: tracker.monitors,
                    selectedMonitor: $selectedMonitor
                )
                .padding(.horizontal)
                .padding(.top, 8)

                Divider()
                    .padding(.vertical, 8)
            }

            // Window list
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filteredWindows) { window in
                        WindowRow(window: window, tracker: tracker)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            // Status bar
            StatusBar(windowCount: filteredWindows.count)
        }
        .frame(minWidth: 350, maxWidth: 500, minHeight: 200, maxHeight: 400)
        .onAppear {
            // Default to main monitor
            selectedMonitor = tracker.monitors.first { $0.isMain } ?? tracker.monitors.first
        }
    }

    private var filteredWindows: [TrackedWindow] {
        if let monitor = selectedMonitor {
            return tracker.windows(on: monitor)
        }
        return tracker.windows
    }
}

struct MonitorSelector: View {
    let monitors: [TrackedMonitor]
    @Binding var selectedMonitor: TrackedMonitor?

    var body: some View {
        HStack {
            Text("Monitor:")
                .foregroundColor(.secondary)

            Picker("", selection: $selectedMonitor) {
                Text("All").tag(nil as TrackedMonitor?)
                ForEach(monitors) { monitor in
                    Text(monitor.name)
                        .tag(monitor as TrackedMonitor?)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

struct WindowRow: View {
    let window: TrackedWindow
    let tracker: WindowTracker

    var body: some View {
        Button(action: activateWindow) {
            HStack(spacing: 10) {
                // App icon
                AppIcon(bundleId: window.appBundleId)
                    .frame(width: 24, height: 24)

                // Window info
                VStack(alignment: .leading, spacing: 2) {
                    Text(window.title ?? "Untitled")
                        .lineLimit(1)
                        .font(.system(size: 13, weight: window.isFocused ? .semibold : .regular))

                    Text(window.appName)
                        .lineLimit(1)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Focus indicator
                if window.isFocused {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(window.isFocused ? Color.accentColor.opacity(0.15) : Color.clear)
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
                .foregroundColor(.secondary)
        }
    }
}

struct StatusBar: View {
    let windowCount: Int

    var body: some View {
        HStack {
            Text("\(windowCount) window\(windowCount == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

#Preview {
    TaskbarContentView(tracker: WindowTracker())
        .frame(width: 400, height: 300)
}
