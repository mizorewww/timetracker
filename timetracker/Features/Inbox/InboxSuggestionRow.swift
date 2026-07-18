import SwiftUI

struct InboxGeneratingSuggestionBar: View {
    var body: some View {
        HStack(spacing: 8) {
            Label {
                Text(.app("inbox.suggestion.generating"))
            } icon: {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
            }
            Spacer(minLength: 8)
            ProgressView()
                .controlSize(.small)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.leading, 44)
        .frame(minHeight: 32)
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
        .padding(.leading, 44)
    }

    private var horizontalLayout: some View {
        HStack(spacing: isCompact ? 6 : 10) {
            suggestionLabel
                .layoutPriority(1)
            Spacer(minLength: 4)
            actions
                .fixedSize()
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            suggestionLabel
            actions
        }
    }

    private var suggestionLabel: some View {
        Label {
            Text(
                String.localizedStringWithFormat(
                    AppStrings.localized("inbox.suggestion.targetFormat"),
                    taskTitle
                )
            )
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "sparkles")
                .foregroundStyle(.blue)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private var actions: some View {
        HStack(spacing: 4) {
            Button(AppStrings.localized("common.dismiss"), action: discard)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(AppStrings.localized("inbox.suggestion.discard"))

            Button(AppStrings.localized("inbox.suggestion.apply"), action: apply)
                .buttonStyle(.plain)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(AppStrings.localized("inbox.suggestion.apply"))
        }
        .font(.footnote)
    }
}

struct InboxSuggestionFailureBar: View {
    let isCompact: Bool
    let retry: () -> Void
    let discard: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: isCompact ? 6 : 10) {
                failureLabel
                    .layoutPriority(1)
                Spacer(minLength: 4)
                actions
            }

            VStack(alignment: .leading, spacing: 0) {
                failureLabel
                actions
            }
        }
        .padding(.leading, 44)
    }

    private var failureLabel: some View {
        Label {
            Text(.app("inbox.suggestion.failed"))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private var actions: some View {
        HStack(spacing: 4) {
            Button(AppStrings.localized("common.dismiss"), action: discard)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(AppStrings.localized("inbox.suggestion.discard"))

            Button(AppStrings.localized("inbox.suggestion.retry"), action: retry)
                .buttonStyle(.plain)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(AppStrings.localized("inbox.suggestion.retry"))
        }
        .font(.footnote)
    }
}
