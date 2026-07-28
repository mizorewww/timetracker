import Foundation

extension TimeTrackerStore {
    /// Ranks every trackable task for compact system surfaces without inheriting
    /// the user's task-tree order. Used tasks lead by frequency and recency;
    /// unused tasks remain deterministic and complete at the end.
    func rankedTrackableTasks(
        excluding excludedIDs: Set<UUID> = []
    ) -> [TaskNode] {
        let availableTasks = tasks.filter {
            isTaskAvailableForTracking($0)
        }
        return TaskUsageRankingService().rankedTasks(
            availableTasks: availableTasks,
            activityByTaskID: taskUsageActivityByTaskID(
                for: availableTasks
            ),
            excluding: excludedIDs
        )
    }

    func taskUsageActivityByTaskID(
        for availableTasks: [TaskNode]
    ) -> [UUID: TaskLedgerActivitySummary] {
        availableTasks.reduce(into: [:]) {
            activityByTaskID,
            task in
            if let activity = rollupDomainStore.activitySummary(
                for: task.id
            ) {
                activityByTaskID[task.id] = activity
            }
        }
    }
}
