import Foundation

/// Deterministic usage and recency ranking shared by compact system surfaces.
///
/// Callers remain responsible for filtering `availableTasks` through the
/// canonical tracking-availability policy before invoking this service.
nonisolated enum TaskUsageRankingService {
    static func rankedTasks(
        availableTasks: [TaskNode],
        activityByTaskID: [UUID: TaskLedgerActivitySummary],
        excluding excludedIDs: Set<UUID> = []
    ) -> [TaskNode] {
        availableTasks
            .filter { excludedIDs.contains($0.id) == false }
            .sorted(byKey: { task in
                let activity = activityByTaskID[task.id]
                return (activity?.segmentCount ?? 0, activity?.lastStartedAt ?? .distantPast, task.id)
            }, by: { lhs, rhs in
                if lhs.0 != rhs.0 {
                    return lhs.0 > rhs.0
                }
                return DatedIdentityOrder.newestFirst((lhs.1, lhs.2), (rhs.1, rhs.2))
            })
    }

    static func frequentRecentTasks(
        availableTasks: [TaskNode],
        rankedTasks: [TaskNode],
        activityByTaskID: [UUID: TaskLedgerActivitySummary],
        excluding excludedIDs: Set<UUID> = [],
        limit: Int
    ) -> [TaskNode] {
        guard limit > 0 else { return [] }

        let historicallyUsedTasks = rankedTasks.filter {
            excludedIDs.contains($0.id) == false &&
                activityByTaskID[$0.id] != nil
        }
        let historicallyUsedIDs = Set(
            historicallyUsedTasks.map(\.id)
        )
        let recentTasks = availableTasks
            .sorted(byKey: { ($0.updatedAt, $0.id) }, by: DatedIdentityOrder.newestFirst)
            .prefix(4)
        let fallbackTasks = recentTasks.filter {
            excludedIDs.contains($0.id) == false &&
                historicallyUsedIDs.contains($0.id) == false
        }
        return Array(
            (historicallyUsedTasks + fallbackTasks).prefix(limit)
        )
    }
}
