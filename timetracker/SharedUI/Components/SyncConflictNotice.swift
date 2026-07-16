import SwiftUI

struct SyncConflictNotice: View {
    let onReview: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.orange)

                Text(.app("sync.state.conflict.title"))
                    .font(.headline)
                    .accessibilityIdentifier("sync.conflict.notice")

                Spacer(minLength: 8)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(AppStrings.localized("common.dismiss"))
                .accessibilityLabel(AppStrings.localized("common.dismiss"))
            }

            HStack(alignment: .bottom, spacing: 12) {
                Text(.app("sync.conflict.notice.message"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Button(AppStrings.localized("sync.conflict.notice.review"), action: onReview)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .accessibilityIdentifier("sync.conflict.notice.review")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.orange.opacity(0.08))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.orange.opacity(0.25), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }
}
