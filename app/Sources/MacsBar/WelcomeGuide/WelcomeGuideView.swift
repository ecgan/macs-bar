import AppKit
import SwiftUI

private enum WelcomeGuideStep: Int, CaseIterable {
    case welcome
    case accessibility
    case placement
    case visibility
    case shortcuts
    case ready

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .accessibility: return "Accessibility"
        case .placement: return "Placement"
        case .visibility: return "Show / Hide"
        case .shortcuts: return "Shortcuts"
        case .ready: return "Ready"
        }
    }
}

struct WelcomeGuideView: View {
    @EnvironmentObject private var permissionManager: AccessibilityPermissionManager
    @EnvironmentObject private var shortcutStorage: ShortcutStorage
    @AppStorage(AppSettings.autoHideEnabledKey) private var autoHideEnabled = false
    @AppStorage(AppSettings.autoHideActivationHeightKey)
    private var autoHideActivationHeight = AppSettings.defaultAutoHideActivationHeight
    @AppStorage(AppSettings.panelLevelKey)
    private var panelLevel = AppSettings.defaultPanelLevel.rawValue
    @AppStorage(AppSettings.barPlacementAreaKey)
    private var barPlacementArea = AppSettings.defaultBarPlacementArea.rawValue

    let isFirstRun: Bool
    let onFinish: () -> Void

    @State private var step = WelcomeGuideStep.welcome

    private var stepIndex: Int {
        WelcomeGuideStep.allCases.firstIndex(of: step) ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 42)
                .padding(.vertical, 28)

            Divider()
            footer
        }
        .frame(width: 720, height: 560)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome to Macs Bar")
                    .font(.headline)
                Text(step.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("Step \(stepIndex + 1) of \(WelcomeGuideStep.allCases.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            welcomeStep
        case .accessibility:
            accessibilityStep
        case .placement:
            placementStep
        case .visibility:
            visibilityStep
        case .shortcuts:
            shortcutsStep
        case .ready:
            readyStep
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 7) {
                ForEach(WelcomeGuideStep.allCases, id: \.self) { item in
                    Circle()
                        .fill(item == step ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: 7, height: 7)
                        .accessibilityLabel(item.title)
                        .accessibilityAddTraits(item == step ? .isSelected : [])
                }
            }

            Spacer()

            if isFirstRun {
                Button("Skip Setup") {
                    onFinish()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if stepIndex > 0 {
                Button("Back") {
                    move(by: -1)
                }
            }

            if step == .ready {
                Button("Finish") {
                    onFinish()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Continue") {
                    move(by: 1)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var welcomeStep: some View {
        VStack(spacing: 22) {
            Text("A taskbar for the windows in your current desktop Space")
                .font(.system(size: 25, weight: .semibold))
                .multilineTextAlignment(.center)

            Text("Macs Bar keeps your open windows visible at the bottom of the screen so you can switch between them with a click or a keyboard shortcut.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 540)

            ScreenPreview(
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

    private var accessibilityStep: some View {
        VStack(spacing: 22) {
            stepTitle(
                "Allow Accessibility access",
                description: "Macs Bar needs this permission to discover open windows, keep the bar updated, activate windows, and listen for global keyboard shortcuts."
            )

            WelcomeCard {
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

    private var placementStep: some View {
        HStack(spacing: 34) {
            VStack(alignment: .leading, spacing: 18) {
                stepTitle(
                    "Choose where the bar appears",
                    description: "Above the Dock is recommended and makes Macs Bar easy to find."
                )

                Picker("Placement", selection: $barPlacementArea) {
                    Text("Above the Dock").tag(BarPlacementArea.visibleFrame.rawValue)
                    Text("Screen edge").tag(BarPlacementArea.screenFrame.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if barPlacementArea == BarPlacementArea.screenFrame.rawValue {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("When the Dock overlaps")
                            .font(.headline)

                        Picker("Dock overlap", selection: $panelLevel) {
                            Text("Behind Dock").tag(PanelLevel.behindDock.rawValue)
                            Text("In front of Dock").tag(PanelLevel.inFrontOfDock.rawValue)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Text("Placing the bar behind the Dock can obscure it when the Dock contains many apps.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label("Keeps Macs Bar outside the area occupied by the Dock.", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ScreenPreview(
                placementArea: BarPlacementArea(rawValue: barPlacementArea) ?? .visibleFrame,
                panelLevel: PanelLevel(rawValue: panelLevel) ?? .behindDock,
                autoHideEnabled: false
            )
            .frame(width: 300, height: 210)
        }
    }

    private var visibilityStep: some View {
        HStack(spacing: 34) {
            VStack(alignment: .leading, spacing: 20) {
                stepTitle(
                    "Keep it visible or reveal it when needed",
                    description: "Macs Bar is always visible by default. Auto-hide reveals it when the pointer reaches the bottom edge."
                )

                Toggle("Automatically hide and show Macs Bar", isOn: $autoHideEnabled)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Activation area")
                        Spacer()
                        Text("\(Int(autoHideActivationHeight)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(
                        value: $autoHideActivationHeight,
                        in: AppSettings.autoHideActivationHeightRange,
                        step: 1
                    )

                    Text("A larger area makes the hidden bar easier to reveal.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!autoHideEnabled)
                .opacity(autoHideEnabled ? 1 : 0.55)

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ScreenPreview(
                placementArea: BarPlacementArea(rawValue: barPlacementArea) ?? .visibleFrame,
                panelLevel: PanelLevel(rawValue: panelLevel) ?? .behindDock,
                autoHideEnabled: autoHideEnabled
            )
            .frame(width: 300, height: 210)
        }
    }

    private var shortcutsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle(
                "Use or customize keyboard shortcuts",
                description: "The defaults work immediately. Click a shortcut to record a different key combination."
            )

            WelcomeCard {
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

    private var readyStep: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            stepTitle(
                "Macs Bar is ready",
                description: "Open a few application windows and look near the bottom of the screen. Click an item in Macs Bar or use your shortcuts to switch windows."
            )

            WelcomeCard {
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

    private func stepTitle(_ title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 24, weight: .semibold))
            Text(description)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func shortcutBinding(for action: ShortcutAction) -> Binding<KeyboardShortcut> {
        Binding(
            get: { shortcutStorage.shortcut(for: action) },
            set: { shortcutStorage.setShortcut($0, for: action) }
        )
    }

    private func move(by offset: Int) {
        let destination = min(
            max(stepIndex + offset, 0),
            WelcomeGuideStep.allCases.count - 1
        )
        step = WelcomeGuideStep.allCases[destination]
    }
}

private struct WelcomeCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            }
    }
}

private struct ScreenPreview: View {
    let placementArea: BarPlacementArea
    let panelLevel: PanelLevel
    let autoHideEnabled: Bool

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let dockHeight = max(24, height * 0.15)
            let menuBarHeight = max(16, height * 0.1)
            let dockWidth = dockHeight * 0.58 * 7 + 5 * 6 + 12
            let barWidth = dockWidth * 0.9
            let barHeight = max(15, height * 0.09)
            let dockBottomInset: CGFloat = 5
            let dockTop = height - dockHeight - dockBottomInset
            let barY = placementArea == .visibleFrame
                ? dockTop - barHeight / 2 - 5
                : height - barHeight / 2 - dockBottomInset

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.18),
                                Color.purple.opacity(0.12),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                previewMenuBar(width: width, height: menuBarHeight)
                    .position(x: width / 2, y: menuBarHeight / 2)
                    .zIndex(3)

                previewBar(width: barWidth, height: barHeight)
                    .opacity(autoHideEnabled ? 0.3 : 1)
                    .position(x: width / 2, y: barY)
                    .zIndex(panelLevel == .inFrontOfDock ? 2 : 0)

                previewDock(height: dockHeight)
                    .position(x: width / 2, y: height - dockHeight / 2 - 5)
                    .zIndex(1)

                if autoHideEnabled {
                    Image(systemName: "cursorarrow.motionlines")
                        .font(.title2)
                        .position(x: width / 2, y: height - 9)
                        .zIndex(3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            autoHideEnabled
                ? "Preview of Macs Bar hidden until the pointer reaches the bottom edge"
                : "Preview of Macs Bar at the bottom of the screen"
        )
    }

    private func previewMenuBar(width: CGFloat, height: CGFloat) -> some View {
        let fontSize = max(6, height * 0.43)

        return HStack(spacing: fontSize * 0.8) {
            Image(systemName: "apple.logo")
                .font(.system(size: fontSize, weight: .semibold))

            Text("Finder")
                .fontWeight(.semibold)
            Text("File")
            Text("Edit")
            Text("View")

            Spacer(minLength: 4)

            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Text("9:41")
                .monospacedDigit()
        }
        .font(.system(size: fontSize))
        .foregroundStyle(Color.primary.opacity(0.78))
        .padding(.horizontal, 8)
        .frame(width: width, height: height)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private func previewBar(width: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { index in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index == 0 ? Color.blue : index == 1 ? Color.orange : Color.green)
                        .frame(width: height * 0.48, height: height * 0.48)
                    Capsule()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: width * 0.17, height: 3)
                }
                .padding(.horizontal, 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.primary.opacity(index == 0 ? 0.13 : 0.05))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .frame(width: width, height: height)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }

    private func previewDock(height: CGFloat) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<7, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        [
                            Color.blue, .cyan, .green, .yellow, .orange, .pink, .purple,
                        ][index].opacity(0.85)
                    )
                    .frame(width: height * 0.58, height: height * 0.58)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: height)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        }
    }
}
