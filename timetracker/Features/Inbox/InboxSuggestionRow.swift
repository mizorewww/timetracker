import SwiftUI

struct InboxGeneratingSuggestionBar: View {
    let itemID: UUID

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
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.leading, AppLayout.minimumInteractiveTarget + 10)
        .frame(minHeight: AppLayout.minimumInteractiveTarget)
        .accessibilityIdentifier("inbox.suggestion.generating.\(itemID.uuidString)")
    }
}

struct InboxSuggestionBar: View {
    let itemID: UUID
    let taskTitle: String
    let iconName: String
    let colorHex: String
    let isCompact: Bool
    let canApply: Bool
    let discard: () -> Void
    let apply: () -> Void

    var body: some View {
        adaptiveLayout
            .padding(.leading, AppLayout.minimumInteractiveTarget + 10)
    }

    @ViewBuilder
    private var adaptiveLayout: some View {
        if isCompact {
            compactLayout
        } else {
            ViewThatFits(in: .horizontal) {
                horizontalLayout
                compactLayout
            }
        }
    }

    private var horizontalLayout: some View {
        HStack(spacing: 10) {
            suggestionLabel
                .frame(minWidth: 160, alignment: .leading)
                .layoutPriority(1)
            Spacer(minLength: 4)
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
            ChecklistItemIcon(
                iconName: iconName,
                colorHex: colorHex,
                style: .solid
            )

            VStack(alignment: .leading, spacing: 2) {
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

                if canApply == false {
                    Text(.app("inbox.suggestion.targetUnavailable"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("inbox.suggestion.ready.\(itemID.uuidString)")
    }

    private var actions: some View {
        HStack(spacing: 4) {
            Button(action: discard) {
                CompactTextActionLabel(
                    title: AppStrings.localized("common.dismiss")
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(AppStrings.localized("inbox.suggestion.discard"))
            .accessibilityIdentifier(
                "inbox.suggestion.discard.\(itemID.uuidString)"
            )

            Button(action: apply) {
                CompactTextActionLabel(
                    title: AppStrings.localized("inbox.suggestion.apply")
                )
            }
            .buttonStyle(.plain)
            .fontWeight(.semibold)
            .foregroundStyle(.blue)
            .disabled(canApply == false)
            .accessibilityLabel(AppStrings.localized("inbox.suggestion.apply"))
            .accessibilityIdentifier(
                "inbox.suggestion.apply.\(itemID.uuidString)"
            )
        }
        .font(.subheadline)
    }
}

struct InboxSuggestionFailureBar: View {
    let itemID: UUID
    let message: String
    let isCompact: Bool
    let retry: () -> Void
    let discard: () -> Void

    var body: some View {
        adaptiveLayout
            .padding(.leading, AppLayout.minimumInteractiveTarget + 10)
    }

    @ViewBuilder
    private var adaptiveLayout: some View {
        if isCompact {
            compactLayout
        } else {
            ViewThatFits(in: .horizontal) {
                horizontalLayout
                compactLayout
            }
        }
    }

    private var horizontalLayout: some View {
        HStack(spacing: 10) {
            failureLabel
                .frame(minWidth: 160, alignment: .leading)
                .layoutPriority(1)
            Spacer(minLength: 4)
            actions
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            failureLabel
            HStack {
                Spacer(minLength: 0)
                actions
            }
        }
    }

    private var failureLabel: some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("inbox.suggestion.failure.\(itemID.uuidString)")
    }

    private var actions: some View {
        HStack(spacing: 4) {
            Button(action: discard) {
                CompactTextActionLabel(
                    title: AppStrings.localized("inbox.suggestion.dismissFailure")
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(
                AppStrings.localized("inbox.suggestion.dismissFailure")
            )
            .accessibilityIdentifier(
                "inbox.suggestion.dismissFailure.\(itemID.uuidString)"
            )

            Button(action: retry) {
                CompactTextActionLabel(
                    title: AppStrings.localized("inbox.suggestion.retry")
                )
            }
            .buttonStyle(.plain)
            .fontWeight(.semibold)
            .foregroundStyle(.blue)
            .accessibilityLabel(AppStrings.localized("inbox.suggestion.retry"))
            .accessibilityIdentifier(
                "inbox.suggestion.retry.\(itemID.uuidString)"
            )
        }
        .font(.subheadline)
    }
}
