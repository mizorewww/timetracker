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
    @State private var editorDraft: TaskEditorDraft?

    init(store: TimeTrackerStore, taskID: UUID, startsEditing: Bool = false) {
        self.store = store
        self.taskID = taskID
        _editorDraft = State(
            initialValue: startsEditing
                ? store.task(for: taskID).map { store.editorDraft(for: $0) }
                : nil
        )
    }

    var body: some View {
        Group {
            if let task = store.task(for: taskID) {
                if let editorDraft {
                    TaskEditorPanel(
                        store: store,
                        initialDraft: editorDraft,
                        onCancel: finishEditing,
                        onSave: { draft in
                            store.saveTaskDraftResult(
                                draft,
                                returnDestination: .tasks
                            )
                        },
                        onSaved: finishEditing
                    )
                } else {
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
                }
            } else {
                ContentUnavailableView(
                    AppStrings.localized("task.empty.selectTask"),
                    systemImage: "checklist"
                )
            }
        }
        .taskDetailNavigation(
            store: store,
            taskID: taskID,
            isEditing: editorDraft != nil,
            beginEditing: beginEditing
        )
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

    private func beginEditing(_ task: TaskNode) {
        editorDraft = store.editorDraft(for: task)
    }

    private func finishEditing() {
        editorDraft = nil
        guard store.tasksRoute?.taskID == taskID,
              store.tasksRoute?.startsEditing == true else {
            return
        }
        store.tasksRoute = .detail(taskID: taskID)
    }
}
