import Foundation
import SwiftUI

extension TaskDetailWorkspace {
    func workspace(for task: TaskNode) -> some View {
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

        return TaskDetailList(
            store: store,
            task: task,
            session: session,
            autosaveController: autosaveController,
            focusedTextField: $focusedTextField,
            focusedChecklistDraftID: $focusedChecklistDraftID,
            snapshot: canKeepDisplayingSnapshot ? snapshot : nil,
            range: rangeSelection(for: task),
            isRefreshing: canKeepDisplayingSnapshot && loadedRequest != request
        )
        .task(id: request) {
            guard loadedRequest != request || snapshot == nil else { return }
            snapshot = store.taskAnalyticsSnapshot(
                for: request,
                now: evaluationDate
            )
            loadedRequest = request
        }
        .task(id: refreshPlan) {
            await waitForRefresh(refreshPlan)
        }
    }

    private func rangeSelection(
        for task: TaskNode
    ) -> Binding<AnalyticsRange> {
        Binding(
            get: { range },
            set: { selectRange($0, for: task) }
        )
    }

    func selectRange(
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

    func waitForRefresh(_ plan: AnalyticsRefreshPlan?) async {
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
