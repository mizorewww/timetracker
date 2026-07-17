import Combine
import Foundation
import SwiftUI

struct TaskDetailView: View {
    @Environment(\.scenePhase) private var scenePhase

    let store: TimeTrackerStore
    let taskID: UUID
    @State private var range: AnalyticsRange = .week
    @State private var liveNow = Date()
    @State private var snapshot: TaskAnalyticsSnapshot?
    @State private var loadedRequest: TaskAnalyticsSnapshotRequest?

    var body: some View {
        Group {
            if let task = store.task(for: taskID) {
                let evaluationDate = liveNow
                let request = store.taskAnalyticsSnapshotRequest(
                    for: task,
                    range: range,
                    now: evaluationDate
                )
                let refreshPlan = scenePhase == .active
                    ? AnalyticsRefreshPlan.next(
                        liveNow: evaluationDate,
                        followsCurrentPeriod: true,
                        liveRefreshBucket: request.liveRefreshBucket
                    )
                    : nil
                TaskDetailList(
                    store: store,
                    task: task,
                    snapshot: loadedRequest == request ? snapshot : nil,
                    range: $range
                )
                .task(id: request) {
                    snapshot = store.taskAnalyticsSnapshot(for: request, now: evaluationDate)
                    loadedRequest = request
                }
                .task(id: refreshPlan) {
                    await waitForRefresh(refreshPlan)
                }
            } else {
                ContentUnavailableView(
                    AppStrings.localized("task.empty.selectTask"),
                    systemImage: "checklist"
                )
            }
        }
        .taskDetailNavigation(store: store, taskID: taskID)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            liveNow = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            liveNow = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in
            liveNow = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            liveNow = Date()
        }
    }

    private func waitForRefresh(_ plan: AnalyticsRefreshPlan?) async {
        guard let plan else { return }
        let delay = max(0, plan.deadline.timeIntervalSinceNow)
        do {
            try await Task.sleep(for: .seconds(delay))
        } catch {
            return
        }
        guard Task.isCancelled == false else { return }
        liveNow = Date()
    }
}

private struct TaskDetailList: View {
    let store: TimeTrackerStore
    let task: TaskNode
    let snapshot: TaskAnalyticsSnapshot?
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

            TaskDetailChecklistSection(store: store, task: task)
            TaskDetailForecastSection(store: store, task: task)

            if let notes = task.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                Section(AppStrings.localized("editor.task.notes")) {
                    Text(notes)
                        .textSelection(.enabled)
                }
            }

            if let snapshot {
                TaskDetailOverviewSection(snapshot: snapshot)
                TaskDetailAnalysisSection(range: $range, snapshot: snapshot)
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
        .contentMargins(
            .bottom,
            16,
            for: .scrollContent
        )
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .accessibilityIdentifier("task.detail")
    }
}
