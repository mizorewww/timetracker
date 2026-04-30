import Foundation

struct RollupStore {
    private let rollupService = TaskRollupService()
    private(set) var taskRollups: [UUID: TaskRollup] = [:]

    mutating func refresh(
        tasks: [TaskNode],
        segments: [TimeSegment],
        checklistItems: [ChecklistItem],
        forecastEligibleTaskIDs: Set<UUID>? = nil,
        now: Date = Date()
    ) {
        taskRollups = rollupService.rollups(
            tasks: tasks,
            segments: segments,
            checklistItems: checklistItems,
            forecastEligibleTaskIDs: forecastEligibleTaskIDs,
            now: now
        )
    }

    mutating func refreshAffected(
        taskIDs: Set<UUID>,
        tasks: [TaskNode],
        segments: [TimeSegment],
        checklistItems: [ChecklistItem],
        forecastEligibleTaskIDs: Set<UUID>? = nil,
        now: Date = Date()
    ) {
        taskRollups = rollupService.rollups(
            updating: taskIDs,
            existingRollups: taskRollups,
            tasks: tasks,
            segments: segments,
            checklistItems: checklistItems,
            forecastEligibleTaskIDs: forecastEligibleTaskIDs,
            now: now
        )
    }

    func rollup(for taskID: UUID) -> TaskRollup? {
        taskRollups[taskID]
    }

    func checklistProgress(for taskID: UUID, checklistItems: [ChecklistItem]) -> ChecklistProgress {
        rollupService.checklistProgress(for: taskID, checklistItems: checklistItems)
    }
}
