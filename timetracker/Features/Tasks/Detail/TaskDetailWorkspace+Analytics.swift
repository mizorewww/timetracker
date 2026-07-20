import Foundation

extension TaskDetailWorkspace {
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
