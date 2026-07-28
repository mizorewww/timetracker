import Foundation

nonisolated struct TaskLedgerActivitySummary: Equatable, Sendable {
    let segmentCount: Int
    let lastStartedAt: Date
}

extension RollupIncrementalIndex {
    mutating func rebuildActivitySummaries() {
        activitySummaryByTaskID.removeAll(keepingCapacity: true)
        for taskID in segmentIDsByTaskID.keys {
            rebuildActivitySummary(for: taskID)
        }
    }

    mutating func rebuildActivitySummary(for taskID: UUID) {
        let snapshots = (segmentIDsByTaskID[taskID] ?? []).compactMap { segmentByID[$0] }
        guard let lastStartedAt = snapshots.lazy.map(\.startedAt).max() else {
            activitySummaryByTaskID.removeValue(forKey: taskID)
            return
        }
        activitySummaryByTaskID[taskID] = TaskLedgerActivitySummary(
            segmentCount: snapshots.count,
            lastStartedAt: lastStartedAt
        )
    }

    func activitySummary(for taskID: UUID) -> TaskLedgerActivitySummary? {
        activitySummaryByTaskID[taskID]
    }
}
