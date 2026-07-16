import SwiftUI

struct TaskDetailView: View {
    let store: TimeTrackerStore
    let taskID: UUID
    @State private var range: AnalyticsRange = .week
    @State private var snapshot: TaskAnalyticsSnapshot?
    @State private var loadedRequest: TaskAnalyticsSnapshotRequest?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let task = store.task(for: taskID) {
                let request = store.taskAnalyticsSnapshotRequest(
                    for: task,
                    range: range,
                    now: context.date
                )
                Group {
                    if let snapshot, loadedRequest == request {
                        TaskDetailList(store: store, task: task, snapshot: snapshot, range: $range)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityLabel(AppStrings.localized("analytics.loading"))
                    }
                }
                .task(id: request) {
                    snapshot = store.taskAnalyticsSnapshot(for: request, now: context.date)
                    loadedRequest = request
                }
            } else {
                ContentUnavailableView(
                    AppStrings.localized("task.empty.selectTask"),
                    systemImage: "checklist"
                )
            }
        }
        .taskDetailNavigation(store: store, taskID: taskID)
    }
}

private struct TaskDetailList: View {
    let store: TimeTrackerStore
    let task: TaskNode
    let snapshot: TaskAnalyticsSnapshot
    @Binding var range: AnalyticsRange

    private var activeSegment: TimeSegment? {
        store.activeSegment(for: task.id)
    }

    var body: some View {
        List {
            Section {
                TaskDetailIdentityRow(store: store, task: task, isRunning: activeSegment != nil)
            }
            .accessibilityIdentifier("task.detail.identity")

            TaskDetailActionsView(store: store, task: task, activeSegment: activeSegment)

            TaskDetailOverviewSection(snapshot: snapshot)
            TaskDetailChecklistSection(store: store, task: task)

            TaskDetailForecastSection(store: store, task: task)
            TaskDetailAnalysisSection(range: $range, snapshot: snapshot)
            TaskDetailRecordsSection(records: snapshot.recentRecords)

            if let notes = task.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                Section(AppStrings.localized("editor.task.notes")) {
                    Text(notes)
                        .textSelection(.enabled)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .accessibilityIdentifier("task.detail")
    }
}
