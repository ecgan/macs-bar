import MacWindowTracker
import SwiftUI

struct PillWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct MacsBarContentView: View {
    @ObservedObject var state: SpaceBarState
    @Environment(\.colorScheme) var colorScheme

    private var pillShape: some Shape {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(spacing: 0) {
                ForEach(state.windows) { window in
                    MacsBarItem(window: window, state: state)
                }
            }
            .padding(.horizontal, 4)
            .frame(minWidth: 32)
            .frame(height: 32)
            .background(.regularMaterial)
            .clipShape(pillShape)
            .overlay(
                pillShape
                    .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 5, x: 0, y: 2)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: PillWidthPreferenceKey.self, value: geo.size.width)
                }
            )
            .contextMenu {
                AppContextMenu()
            }
            .opacity(state.windows.isEmpty ? 0 : 1)
            .animation(.easeInOut(duration: 0.2), value: state.windows.isEmpty)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .onPreferenceChange(PillWidthPreferenceKey.self) { width in
            state.pillWidth = width
        }
    }
}

struct MacsBarItem: View {
    let window: TrackedWindow
    let state: SpaceBarState
    @Environment(\.colorScheme) var colorScheme

    @ViewBuilder
    private var activeItemBackground: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.white)
            .shadow(color: Color.black.opacity(0.12), radius: 1, x: 0, y: 1)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
    }

    var body: some View {
        Button(action: activateWindow) {
            HStack(spacing: 6) {
                AppIcon(bundleId: window.appBundleId)
                    .frame(width: 20, height: 20)

                Text(window.title ?? window.appName)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: 172, alignment: .leading)
            .background(
                Group {
                    if window.isFocused {
                        activeItemBackground
                    }
                }
            )
            .padding(4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focusable(false)
        .contextMenu {
            Button("Close Window") {
                state.closeWindow(window)
            }
        }
    }

    private func activateWindow() {
        Task {
            await state.activateWindow(window)
        }
    }
}

struct AppIcon: View {
    let bundleId: String?

    var body: some View {
        if let bundleId,
            let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        {
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
