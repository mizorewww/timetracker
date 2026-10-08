import Foundation
import SwiftUI

struct TaskDetailQuantitySections: View {
    let readModel: TaskQuantityDetailReadModel
    let addEntry: (TaskQuantityDetailSnapshot) -> Void
    let editEntry: (
        TaskQuantityDetailSnapshot,
        TaskQuantityEntrySnapshot
    ) -> Void

    var body: some View {
        switch readModel {
        case .none:
            EmptyView()
        case .incomplete:
            Section(AppStrings.localized("task.quantity.detail.section")) {
                TaskEditorInlineErrorMessage(
                    message: TaskProgressDraftMutationError
                        .incompleteQuantityGraph.localizedDescription,
                    accessibilityIdentifier:
                    "task.detail.quantity.sync.error"
                )
            }
        case let .available(detail):
            summarySection(detail)
            historySection(detail)
        }
    }

    private func summarySection(
        _ detail: TaskQuantityDetailSnapshot
    ) -> some View {
        Section {
            TaskDetailQuantitySummary(progress: detail.progress)
            recurrenceContext(detail.recurrenceRole)

            if detail.progress.isRecordingAllowed {
                Button {
                    addEntry(detail)
                } label: {
                    Label(
                        AppStrings.localized("task.quantity.detail.record"),
                        systemImage: "plus.circle.fill"
                    )
                }
                .accessibilityIdentifier("task.detail.quantity.record")
            }
        } header: {
            Text(.app("task.quantity.detail.section"))
        }
    }

    @ViewBuilder
    private func recurrenceContext(
        _ role: TaskQuantityRecurrenceRole
    ) -> some View {
        switch role {
        case .ordinary:
            EmptyView()
        case .template:
            Label(
                AppStrings.localized("task.quantity.detail.template"),
                systemImage: "calendar.badge.clock"
            )
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("task.detail.quantity.template")
        case let .generated(occurrence):
            LabeledContent(
                AppStrings.localized("task.quantity.detail.occurrence"),
                value: occurrenceDateText(occurrence)
            )
            .accessibilityIdentifier("task.detail.quantity.occurrence")
        }
    }

    @ViewBuilder
    private func historySection(
        _ detail: TaskQuantityDetailSnapshot
    ) -> some View {
        if detail.entries.isEmpty == false {
            Section(AppStrings.localized("task.quantity.detail.history")) {
                ForEach(detail.entries) { entry in
                    if detail.progress.isRecordingAllowed {
                        Button {
                            editEntry(detail, entry)
                        } label: {
                            TaskQuantityEntryRow(
                                entry: entry,
                                unitLabel: detail.progress.unitLabel
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            "task.detail.quantity.entry.\(entry.id.uuidString)"
                        )
                    } else {
                        TaskQuantityEntryRow(
                            entry: entry,
                            unitLabel: detail.progress.unitLabel,
                            showsNavigationChevron: false
                        )
                        .accessibilityIdentifier(
                            "task.detail.quantity.entry.\(entry.id.uuidString)"
                        )
                    }
                }
            }
        }
    }

    private func occurrenceDateText(
        _ occurrence: TaskRecurrenceOccurrenceSnapshot
    ) -> String {
        occurrence.formattedDateText()
    }
}

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
