import Foundation

/// Deterministic usage and recency ranking shared by compact system surfaces.
///
/// Callers remain responsible for filtering `availableTasks` through the
/// canonical tracking-availability policy before invoking this service.
nonisolated struct TaskUsageRankingService {
    func rankedTasks(
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
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    func frequentRecentTasks(
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
                return $0.id.uuidString < $1.id.uuidString
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

    /// Preserves the pinned-first array order consumed by older Watch builds.
    func legacyWatchTaskOrder(
        availableTasks: [TaskNode],
        rankedTasks: [TaskNode],
        activityByTaskID: [UUID: TaskLedgerActivitySummary],
        quickStartTaskIDs: [UUID],
        taskPathByID: [UUID: String]
    ) -> [TaskNode] {
        let pinnedTasks = quickStartTaskIDs.compactMap { taskID in
            availableTasks.first { $0.id == taskID }
        }
        let pinnedIDs = Set(pinnedTasks.map(\.id))
        let recentFillTasks = frequentRecentTasks(
            availableTasks: availableTasks,
            rankedTasks: rankedTasks,
            activityByTaskID: activityByTaskID,
            excluding: pinnedIDs,
            limit: availableTasks.count
        )
        let rankedIDs = Set(
            (pinnedTasks + recentFillTasks).map(\.id)
        )
        let remainingTasks = availableTasks
            .filter { rankedIDs.contains($0.id) == false }
            .sorted { lhs, rhs in
                let lhsPath = taskPathByID[lhs.id] ?? lhs.title
                let rhsPath = taskPathByID[rhs.id] ?? rhs.title
                let comparison =
                    lhsPath.localizedStandardCompare(rhsPath)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        return pinnedTasks + recentFillTasks + remainingTasks
    }
}
