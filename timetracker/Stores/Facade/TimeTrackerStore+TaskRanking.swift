import Foundation

extension TimeTrackerStore {
    /// Ranks every trackable task for compact system surfaces without inheriting
    /// the user's task-tree order. Used tasks lead by frequency and recency;
    /// unused tasks remain deterministic and complete at the end.
    func rankedTrackableTasks(
        excluding excludedIDs: Set<UUID> = []
    ) -> [TaskNode] {
        let availableTasks = tasks.filter {
            isTaskAvailableForTracking($0) &&
                !excludedIDs.contains($0.id)
        }

        return availableTasks.sorted { lhs, rhs in
            let lhsActivity = rollupDomainStore.activitySummary(for: lhs.id)
            let rhsActivity = rollupDomainStore.activitySummary(for: rhs.id)
            let lhsSegmentCount = lhsActivity?.segmentCount ?? 0
            let rhsSegmentCount = rhsActivity?.segmentCount ?? 0

            if lhsSegmentCount != rhsSegmentCount {
                return lhsSegmentCount > rhsSegmentCount
            }

            let lhsLastStartedAt = lhsActivity?.lastStartedAt ?? .distantPast
            let rhsLastStartedAt = rhsActivity?.lastStartedAt ?? .distantPast
            if lhsLastStartedAt != rhsLastStartedAt {
                return lhsLastStartedAt > rhsLastStartedAt
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
