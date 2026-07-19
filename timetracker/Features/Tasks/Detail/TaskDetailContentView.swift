import SwiftUI

struct TaskDetailList: View {
    let store: TimeTrackerStore
    let task: TaskNode
    let snapshot: TaskAnalyticsSnapshot?
    @Binding var range: AnalyticsRange
    let isRefreshing: Bool

    var body: some View {
        List {
            Section {
                TaskDetailIdentityRow(
                    store: store,
                    task: task
                )
            }

            TaskDetailTrackingAvailabilitySection(store: store, task: task)

            TaskDetailChecklistSection(store: store, task: task)
            TaskDetailForecastSection(store: store, task: task)

            if let notes = task.notes?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ), !notes.isEmpty {
                Section(AppStrings.localized("editor.task.notes")) {
                    TaskNotesMarkdownPreview(markdown: notes)
                }
            }

            if let snapshot {
                TaskDetailOverviewSection(snapshot: snapshot)
                TaskDetailAnalysisSection(
                    range: $range,
                    snapshot: snapshot,
                    isRefreshing: isRefreshing
                )
                TaskDetailRecordsSection(records: snapshot.recentRecords)
            } else {
                Section(AppStrings.localized("task.detail.analysis")) {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(AppStrings.localized("analytics.loading"))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("task.detail.analyticsLoading")
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .contentMargins(.bottom, 16, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .accessibilityIdentifier("task.detail")
    }
}
