import Foundation

extension TimeTrackerStore {
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
