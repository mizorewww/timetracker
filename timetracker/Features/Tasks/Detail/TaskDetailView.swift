import Combine
import Foundation
import SwiftUI

struct TaskDetailView: View {
    @Environment(\.scenePhase) private var scenePhase

    let store: TimeTrackerStore
    let taskID: UUID
    let returnDestination: TimeTrackerStore.DesktopDestination
    @State private var range: AnalyticsRange = .week
    @State private var liveNow = Date()
    @State private var snapshot: TaskAnalyticsSnapshot?
    @State private var loadedRequest: TaskAnalyticsSnapshotRequest?
    @State private var editorDraft: TaskEditorDraft?

    init(
        store: TimeTrackerStore,
        taskID: UUID,
        startsEditing: Bool = false,
        returnDestination: TimeTrackerStore.DesktopDestination = .tasks
    ) {
        self.store = store
        self.taskID = taskID
        self.returnDestination = returnDestination
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
                                returnDestination: returnDestination
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
                    let canKeepDisplayingSnapshot = loadedRequest.map {
                        $0.canRemainVisible(whileLoading: request)
                    } ?? false
                    let rangeSelection = Binding(
                        get: { range },
                        set: { selectedRange in
                            selectRange(
                                selectedRange,
                                for: task
                            )
                        }
                    )
                    TaskDetailList(
                        store: store,
                        task: task,
                        snapshot: canKeepDisplayingSnapshot ? snapshot : nil,
                        range: rangeSelection,
                        isRefreshing: canKeepDisplayingSnapshot && loadedRequest != request
                    )
                    .task(id: request) {
                        guard loadedRequest != request || snapshot == nil else { return }
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
            beginEditing: beginEditing,
            preservingDestination: returnDestination
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

    private func selectRange(
        _ selectedRange: AnalyticsRange,
        for task: TaskNode
    ) {
        guard selectedRange != range else { return }
        let evaluationDate = Date()
        let request = store.taskAnalyticsSnapshotRequest(
            for: task,
            range: selectedRange,
            now: evaluationDate
        )
        guard let resolvedSnapshot = store.taskAnalyticsSnapshot(
            for: request,
            now: evaluationDate
        ) else {
            snapshot = nil
            loadedRequest = nil
            range = selectedRange
            return
        }

        // Publish matching evidence before changing the Picker selection so the
        // List never passes through a structurally different loading state.
        snapshot = resolvedSnapshot
        loadedRequest = request
        range = selectedRange
        liveNow = evaluationDate
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
