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
            WelcomeGuideWelcomeStep()
        case .accessibility:
            WelcomeGuideAccessibilityStep()
        case .placement:
            WelcomeGuidePlacementStep(
                barPlacementArea: $barPlacementArea,
                panelLevel: $panelLevel
            )
        case .visibility:
            WelcomeGuideVisibilityStep(
                autoHideEnabled: $autoHideEnabled,
                autoHideActivationHeight: $autoHideActivationHeight,
                barPlacementArea: barPlacementArea,
                panelLevel: panelLevel
            )
        case .shortcuts:
            WelcomeGuideShortcutsStep()
        case .ready:
            WelcomeGuideReadyStep(
                barPlacementArea: barPlacementArea,
                autoHideEnabled: autoHideEnabled
            )
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

    private func move(by offset: Int) {
        let destination = min(
            max(stepIndex + offset, 0),
            WelcomeGuideStep.allCases.count - 1
        )
        step = WelcomeGuideStep.allCases[destination]
    }
}
