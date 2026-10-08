import Foundation
import SwiftUI

extension TaskDetailWorkspace {
    func workspace(for task: TaskNode) -> some View {
        TaskDetailAnalyticsWorkspace(
            store: store,
            task: task,
            session: session,
            autosaveController: autosaveController,
            focusedTextField: $focusedTextField,
            focusedChecklistDraftID: $focusedChecklistDraftID
        )
    }
}

private struct TaskDetailAnalyticsWorkspace: View {
    @Environment(\.scenePhase) private var scenePhase

    let store: TimeTrackerStore
    let task: TaskNode
    let session: TaskEditorSession
    let autosaveController: TaskDetailAutosaveController
    let focusedTextField: FocusState<TaskEditorTextField?>.Binding
    let focusedChecklistDraftID: FocusState<UUID?>.Binding

    @State private var range: AnalyticsRange = .week
    @State private var liveNow = Date()

    var body: some View {
        let evaluationDate = liveNow
        let request = store.taskAnalyticsSnapshotRequest(
            for: task,
            range: range,
            referenceDate: evaluationDate,
            liveNow: evaluationDate
        )
        let snapshot = store.taskAnalyticsSnapshot(
            for: request,
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
            session: session,
            autosaveController: autosaveController,
            focusedTextField: focusedTextField,
            focusedChecklistDraftID: focusedChecklistDraftID,
            snapshot: snapshot,
            range: $range
        )
        .task(id: refreshPlan) {
            await waitForRefresh(refreshPlan)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            liveNow = Date()
        }
        .onSystemClockChange {
            liveNow = Date()
        }
    }

    @MainActor
    private func waitForRefresh(_ plan: AnalyticsRefreshPlan?) async {
        guard let plan else { return }
        let delay = max(0, plan.deadline.timeIntervalSinceNow)
        do {
            try await Task.sleep(for: .seconds(delay))
        } catch {
            return
        }
        liveNow = Date()
    }
}
