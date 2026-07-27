import SwiftUI

struct SettingsStatusPresentation {
    let title: String
    let message: String
    let symbolName: String
    let tint: Color
    var showsProgress = false
}

struct SettingsStatusRow: View {
    let presentation: SettingsStatusPresentation

    init(presentation: SettingsStatusPresentation) {
        self.presentation = presentation
    }

    init(feedback: SyncFeedback) {
        presentation = SettingsStatusPresentation(
            title: feedback.title,
            message: feedback.message,
            symbolName: feedback.state.symbolName,
            tint: Self.tint(for: feedback.state),
            showsProgress: feedback.state == .syncing
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            statusIcon
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(presentation.message)
                    .font(messageFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.title)
        .accessibilityValue(presentation.message)
        .settingsRowSeparatorAligned()
    }

    private var messageFont: Font {
        #if os(macOS)
        .callout
        #else
        .caption
        #endif
    }

    @ViewBuilder
    private var statusIcon: some View {
        if presentation.showsProgress {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: presentation.symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(presentation.tint)
                .accessibilityHidden(true)
        }
    }

    private static func tint(for state: SyncFeedbackState) -> Color {
        switch state {
        case .available, .recentlySynced:
            .green
        case .syncing:
            .blue
        case .offline, .needsRestart:
            .orange
        case .failed, .temporaryStore, .conflict:
            .red
        case .localOnly:
            .secondary
        }
    }
}
