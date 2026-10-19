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
    let store: TimeTrackerStore
    let task: TaskNode
    let session: TaskEditorSession
    let autosaveController: TaskDetailAutosaveController
    let focusedTextField: FocusState<TaskEditorTextField?>.Binding
    let focusedChecklistDraftID: FocusState<UUID?>.Binding

    @State private var range: AnalyticsRange = .week
    @State private var liveNow = Date()
    @State private var loaded: (request: TaskAnalyticsSnapshotRequest, snapshot: TaskAnalyticsSnapshot?)?

    var body: some View {
        let request = store.taskAnalyticsSnapshotRequest(
            for: task,
            range: range,
            referenceDate: liveNow,
            liveNow: liveNow
        )
        // Keep the previous result on screen for the one frame a cache miss
        // takes to resolve, like the Analytics page does.
        let snapshot = store.cachedTaskAnalyticsSnapshot(for: request) ?? loaded?.snapshot
        let clockDeadline = LiveClockDeadline.next(
            after: liveNow,
            isLive: request.liveRefreshBucket != nil
        )

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
        .task(id: request) {
            let snapshot = store.taskAnalyticsSnapshot(for: request, now: liveNow)
            guard Task.isCancelled == false else { return }
            loaded = (request, snapshot)
        }
        .liveClock($liveNow, until: clockDeadline)
    }
}
