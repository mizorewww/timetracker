import SwiftUI

struct SettingsRowIcon: View {
    let systemImage: String
    var tint: Color = .accentColor
    var secondaryTint: Color?

    var body: some View {
        Group {
            if let secondaryTint {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(tint, secondaryTint)
            } else {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
            }
        }
        .font(.body.weight(.semibold))
        .frame(width: 28, height: 28)
    }
}

struct SettingsRowLabel: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 12) {
            SettingsRowIcon(systemImage: systemImage, tint: tint)
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SettingsValueRow: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 12) {
            SettingsRowIcon(systemImage: systemImage, tint: tint)

            Text(title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct SettingsTextFieldRow: View {
    let title: String
    @Binding var text: String
    let systemImage: String
    var tint: Color = .accentColor
    var isSecure = false

    var body: some View {
        LabeledContent {
            Group {
                if isSecure {
                    SecureField(title, text: $text)
                } else {
                    TextField(title, text: $text)
                }
            }
            .labelsHidden()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()
        } label: {
            SettingsRowLabel(title: title, systemImage: systemImage, tint: tint)
        }
    }
}

struct SettingsNumberFieldRow: View {
    let title: String
    let value: Binding<Int>
    let formatter: NumberFormatter
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        LabeledContent {
            TextField(title, value: value, formatter: formatter)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
        } label: {
            SettingsRowLabel(title: title, systemImage: systemImage, tint: tint)
        }
    }
}

struct SettingsActionLabel: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor
    var secondaryTint: Color?
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 12) {
            SettingsRowIcon(systemImage: systemImage, tint: tint, secondaryTint: secondaryTint)

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
