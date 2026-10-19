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
            .sorted { lhs, rhs in
                let lhsActivity = activityByTaskID[lhs.id]
                let rhsActivity = activityByTaskID[rhs.id]
                let lhsSegmentCount = lhsActivity?.segmentCount ?? 0
                let rhsSegmentCount = rhsActivity?.segmentCount ?? 0
                if lhsSegmentCount != rhsSegmentCount {
                    return lhsSegmentCount > rhsSegmentCount
                }

                let lhsLastStartedAt =
                    lhsActivity?.lastStartedAt ?? .distantPast
                let rhsLastStartedAt =
                    rhsActivity?.lastStartedAt ?? .distantPast
                if lhsLastStartedAt != rhsLastStartedAt {
                    return lhsLastStartedAt > rhsLastStartedAt
                }
                return lhs.id < rhs.id
            }
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
            .sorted {
                if $0.updatedAt != $1.updatedAt {
                    return $0.updatedAt > $1.updatedAt
                }
                return $0.id < $1.id
            }
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
