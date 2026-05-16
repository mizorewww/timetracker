import SwiftUI

struct SettingsActionLabel: View {
    let title: String
    let systemImage: String
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)

            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement(children: .combine)
    }
}

struct SettingsStatusRow: View {
    let feedback: SyncFeedback

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            statusIcon
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(feedback.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(feedback.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if feedback.state == .syncing {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: feedback.state.symbolName)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
        }
    }

    private var tint: Color {
        switch feedback.state {
        case .available, .recentlySynced:
            return .green
        case .syncing:
            return .blue
        case .offline, .needsRestart:
            return .orange
        case .failed, .temporaryStore, .conflict:
            return .red
        case .localOnly:
            return .secondary
        }
    }
}
