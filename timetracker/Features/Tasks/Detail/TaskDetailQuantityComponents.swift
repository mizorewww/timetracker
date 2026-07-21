import SwiftUI

struct TaskDetailQuantitySummary: View {
    let progress: TaskQuantityProgressSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(.app("editor.checklist.completed"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(amount(progress.totalAmount))
                        .font(.title3.weight(.semibold).monospacedDigit())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(.app("task.quantity.editor.target"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(amount(progress.targetAmount))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: progress.fractionCompleted)
                .accessibilityIdentifier("task.detail.quantity.progress")
                .accessibilityLabel(
                    AppStrings.localized("task.quantity.detail.progress")
                )
                .accessibilityValue(progressAccessibilityValue)
            LabeledContent(
                AppStrings.localized("task.quantity.detail.remaining"),
                value: amount(progress.remainingAmount)
            )
        }
    }

    private func amount(_ value: Int64) -> String {
        "\(value.formatted()) \(progress.unitLabel)"
    }

    private var progressAccessibilityValue: String {
        String.localizedStringWithFormat(
            AppStrings.localized("task.quantity.detail.progressFormat"),
            progress.totalAmount,
            progress.targetAmount,
            progress.unitLabel
        )
    }
}

struct TaskQuantityEntryRow: View {
    let entry: TaskQuantityEntrySnapshot
    let unitLabel: String
    var showsNavigationChevron = true

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(entry.amount.formatted()) \(unitLabel)")
                    .font(.body.weight(.medium).monospacedDigit())
                Text(
                    entry.recordedAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if showsNavigationChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}
