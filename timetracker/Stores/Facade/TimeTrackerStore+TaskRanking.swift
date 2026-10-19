import Foundation

nonisolated struct TaskLedgerActivitySummary: Equatable, Sendable {
    let segmentCount: Int
    let lastStartedAt: Date
}

extension TimeTrackerStore {
    func taskUsageActivityByTaskID(
        for availableTasks: [TaskNode]
    ) -> [UUID: TaskLedgerActivitySummary] {
        availableTasks.reduce(into: [:]) { activityByTaskID, task in
            let snapshots = ledgerDomainStore.snapshots(forTaskID: task.id)
                .filter { readableLedgerSegmentIDs.contains($0.id) }
            if let lastStartedAt = snapshots.lazy.map(\.startedAt).max() {
                activityByTaskID[task.id] = TaskLedgerActivitySummary(
                    segmentCount: snapshots.count,
                    lastStartedAt: lastStartedAt
                )
            }
        }
    }
}
