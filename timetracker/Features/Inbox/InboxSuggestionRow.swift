import SwiftUI

struct InboxGeneratingSuggestionBar: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.blue)
            Text(.app("inbox.suggestion.generating"))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            ProgressView()
                .controlSize(.small)
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(InboxSuggestionBackground())
    }
}

struct InboxSuggestionBar: View {
    let taskTitle: String
    let isCompact: Bool
    let discard: () -> Void
    let apply: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalLayout
            compactLayout
        }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(InboxSuggestionBackground())
    }

    private var horizontalLayout: some View {
        HStack(spacing: isCompact ? 6 : 10) {
            suggestionLabel
                .layoutPriority(1)
            Spacer(minLength: isCompact ? 4 : 8)
            actions
                .fixedSize()
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            suggestionLabel
            HStack {
                Spacer(minLength: 0)
                actions
            }
        }
    }

    private var suggestionLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.body.weight(.semibold))
                .foregroundStyle(.blue)

            suggestionText
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }
        .font(.subheadline)
    }

    private var suggestionText: Text {
        let prefix = Text(AppStrings.localized("inbox.suggestion.prefix"))
            .foregroundStyle(.secondary)
        let title = Text(taskTitle)
            .fontWeight(.semibold)
            .foregroundStyle(.blue)
        return Text("\(prefix) \(title)")
    }

    private var actions: some View {
        HStack(spacing: isCompact ? 8 : 12) {
            Button(action: discard) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: isCompact ? 30 : 32, height: isCompact ? 30 : 32)
                    .background(Color.secondary.opacity(0.12), in: Circle())
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.localized("inbox.suggestion.discard"))

            Button(action: apply) {
                Image(systemName: "checkmark")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: isCompact ? 30 : 32, height: isCompact ? 30 : 32)
                    .background(Color.blue, in: Circle())
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.localized("inbox.suggestion.apply"))
        }
    }
}

struct InboxSuggestionFailureBar: View {
    let isCompact: Bool
    let retry: () -> Void
    let discard: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: isCompact ? 8 : 10) {
                failureLabel
                    .layoutPriority(1)

                Spacer(minLength: 4)
                actions
            }

            VStack(alignment: .leading, spacing: 8) {
                failureLabel
                HStack {
                    Spacer(minLength: 0)
                    actions
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(InboxSuggestionBackground())
    }

    private var failureLabel: some View {
        Label {
            Text(.app("inbox.suggestion.failed"))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var actions: some View {
        HStack(spacing: isCompact ? 8 : 10) {
            Button(action: discard) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(AppStrings.localized("inbox.suggestion.discard"))

            Button(action: retry) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .accessibilityLabel(AppStrings.localized("inbox.suggestion.retry"))
        }
    }
}

private struct InboxSuggestionBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: AppLayout.cardRadius, style: .continuous)
            .fill(AppColors.cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: AppLayout.cardRadius, style: .continuous)
                    .stroke(AppColors.border)
            }
    }
}
