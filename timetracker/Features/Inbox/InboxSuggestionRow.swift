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
        VStack(alignment: .leading, spacing: 8) {
            suggestionLabel
                .padding(.leading, AppLayout.minimumInteractiveTarget + 10)
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var suggestionLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(.app("inbox.suggestion.label"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()

                ChecklistItemIcon(
                    iconName: iconName,
                    colorHex: colorHex,
                    style: .solid
                )

                Text(taskTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                String.localizedStringWithFormat(
                    AppStrings.localized("inbox.suggestion.targetFormat"),
                    taskTitle
                )
            )
            .accessibilityIdentifier("inbox.suggestion.ready.\(itemID.uuidString)")

            if canApply == false {
                Text(.app("inbox.suggestion.targetUnavailable"))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            discardButton
            Spacer(minLength: 8)
            applyButton
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private var discardButton: some View {
        if isCompact {
            compactActionButton(
                systemImage: "xmark",
                accessibilityLabel: AppStrings.localized("inbox.suggestion.discard"),
                identifier: "inbox.suggestion.discard.\(itemID.uuidString)",
                action: discard
            )
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .frame(
                width: AppLayout.minimumInteractiveTarget,
                height: AppLayout.minimumInteractiveTarget
            )
        } else {
            regularActionButton(
                title: AppStrings.localized("common.dismiss"),
                systemImage: "xmark",
                accessibilityLabel: AppStrings.localized("inbox.suggestion.discard"),
                identifier: "inbox.suggestion.discard.\(itemID.uuidString)",
                action: discard
            )
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var applyButton: some View {
        if isCompact {
            compactActionButton(
                systemImage: "checkmark",
                accessibilityLabel: AppStrings.localized("inbox.suggestion.apply"),
                identifier: "inbox.suggestion.apply.\(itemID.uuidString)",
                action: apply
            )
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .frame(
                width: AppLayout.minimumInteractiveTarget,
                height: AppLayout.minimumInteractiveTarget
            )
            .disabled(canApply == false)
        } else {
            regularActionButton(
                title: AppStrings.localized("inbox.suggestion.apply"),
                systemImage: "checkmark",
                accessibilityLabel: AppStrings.localized("inbox.suggestion.apply"),
                identifier: "inbox.suggestion.apply.\(itemID.uuidString)",
                action: apply
            )
            .fontWeight(.semibold)
            .foregroundStyle(.blue)
            .disabled(canApply == false)
        }
    }

    private func compactActionButton(
        systemImage: String,
        accessibilityLabel: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(
                    width: AppLayout.minimumInteractiveTarget - 14,
                    height: AppLayout.minimumInteractiveTarget - 14
                )
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier)
    }

    private func regularActionButton(
        title: String,
        systemImage: String,
        accessibilityLabel: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(minHeight: AppLayout.minimumInteractiveTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier)
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
