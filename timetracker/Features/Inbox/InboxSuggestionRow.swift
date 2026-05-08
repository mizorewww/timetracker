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
        horizontalLayout
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

    private var suggestionLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.body.weight(.semibold))
                .foregroundStyle(.blue)

            Text(AppStrings.localized("inbox.suggestion.prefix"))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Text(taskTitle)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
        }
        .font(.subheadline)
        .minimumScaleFactor(0.78)
    }

    private var actions: some View {
        HStack(spacing: isCompact ? 8 : 12) {
            Button(role: .destructive, action: discard) {
                Image(systemName: "xmark")
                    .font(.system(size: isCompact ? 13 : 14, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: isCompact ? 34 : 38, height: isCompact ? 34 : 38)
                    .background(Color.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.localized("inbox.suggestion.discard"))

            Button(action: apply) {
                Image(systemName: "checkmark")
                    .font(.system(size: isCompact ? 14 : 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: isCompact ? 34 : 38, height: isCompact ? 34 : 38)
                    .background(Color.blue, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.localized("inbox.suggestion.apply"))
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
