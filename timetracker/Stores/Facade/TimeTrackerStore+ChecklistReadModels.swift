import Foundation

extension TimeTrackerStore {
    func checklistItems(for taskID: UUID) -> [ChecklistItem] {
        checklistDomainStore.items(for: taskID)
    }

    func checklistVisual(for item: ChecklistItem) -> ChecklistItemVisual? {
        checklistDomainStore.visual(for: item.id)
    }

    func checklistProgress(for taskID: UUID) -> ChecklistProgress {
        if let cached = rollupDomainStore.rollup(for: taskID)?.checklistProgress {
            return cached
        }
        let items = checklistItems(for: taskID)
        return ChecklistProgress(
            taskID: taskID,
            totalCount: items.count,
            completedCount: items.lazy.filter(\.isCompleted).count
        )
    }

    func rollup(for taskID: UUID) -> TaskRollup? {
        rollupDomainStore.rollup(for: taskID)
    }

    func forecastDisplayItems(limit: Int? = nil) -> [ForecastDisplayItem] {
        ForecastDisplayService.displayItems(tasks: tasks, rollups: rollupDomainStore.taskRollups, limit: limit)
    }

    func forecastDisplayItem(for taskID: UUID) -> ForecastDisplayItem? {
        ForecastDisplayService.displayItem(for: taskID, tasks: tasks, rollups: rollupDomainStore.taskRollups)
    }
}
