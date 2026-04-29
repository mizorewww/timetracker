import Foundation

struct RollupStore {
    private let rollupService = TaskRollupService()
    private(set) var taskRollups: [UUID: TaskRollup] = [:]

    mutating func refresh(tasks: [TaskNode], segments: [TimeSegment], checklistItems: [ChecklistItem], now: Date = Date()) {
        taskRollups = rollupService.rollups(tasks: tasks, segments: segments, checklistItems: checklistItems, now: now)
    }

    func rollup(for taskID: UUID) -> TaskRollup? {
        taskRollups[taskID]
    }

    func checklistProgress(for taskID: UUID, checklistItems: [ChecklistItem]) -> ChecklistProgress {
        rollupService.checklistProgress(for: taskID, checklistItems: checklistItems)
    }
}
