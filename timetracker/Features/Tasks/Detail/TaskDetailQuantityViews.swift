import Foundation
import SwiftUI

struct TaskDetailQuantitySections: View {
    let readModel: TaskQuantityDetailReadModel
    let addEntry: (TaskQuantityDetailSnapshot) -> Void
    let editEntry: (
        TaskQuantityDetailSnapshot,
        TaskQuantityEntrySnapshot
    ) -> Void

    @ViewBuilder
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
        case .available(let detail):
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
        case .generated(let occurrence):
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
