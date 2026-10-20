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
                return (count: activity?.segmentCount ?? 0, lastStartedAt: activity?.lastStartedAt ?? .distantPast, id: task.id)
            }, by: { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                if lhs.lastStartedAt != rhs.lastStartedAt {
                    return lhs.lastStartedAt > rhs.lastStartedAt
                }
                return lhs.id < rhs.id
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
