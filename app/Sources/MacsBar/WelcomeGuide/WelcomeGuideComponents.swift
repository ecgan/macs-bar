import SwiftUI

struct WelcomeGuideStepTitle: View {
    let title: String
    let description: String

    init(_ title: String, description: String) {
        self.title = title
        self.description = description
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 24, weight: .semibold))
            Text(description)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WelcomeGuideCard<Content: View>: View {
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

struct WelcomeGuideScreenPreview: View {
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
