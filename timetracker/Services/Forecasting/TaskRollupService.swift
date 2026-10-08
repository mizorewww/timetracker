import Foundation

struct TaskRollupService {
    func checklistProgress(for taskID: UUID, checklistItems: [ChecklistItem]) -> ChecklistProgress {
        let items = checklistItems
            .visibleDeduplicatedByID()
            .filter { $0.taskID == taskID }
        return ChecklistProgress(
            taskID: taskID,
            totalCount: items.count,
            completedCount: items.filter(\.isCompleted).count
        )
    }
}
