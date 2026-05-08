import Foundation

extension TimeTrackerStore {
    func checklistItems(for taskID: UUID) -> [ChecklistItem] {
        checklistByTaskID[taskID] ?? []
    }

    func checklistVisual(for item: ChecklistItem) -> ChecklistItemVisual? {
        checklistVisualByItemID[item.id]
    }

    func checklistIconName(for item: ChecklistItem) -> String {
        ChecklistVisualSanitizer.sanitizedIcon(checklistVisual(for: item)?.iconName)
    }

    func checklistColorHex(for item: ChecklistItem) -> String {
        ChecklistVisualSanitizer.sanitizedColor(checklistVisual(for: item)?.colorHex)
    }

    func checklistProgress(for taskID: UUID) -> ChecklistProgress {
        rollupDomainStore.checklistProgress(for: taskID, checklistItems: checklistItems)
    }

    func rollup(for taskID: UUID) -> TaskRollup? {
        rollupDomainStore.rollup(for: taskID)
    }

    func forecastDisplayItems(limit: Int? = nil) -> [ForecastDisplayItem] {
        forecastDisplayService.displayItems(tasks: tasks, rollups: rollupDomainStore.taskRollups, limit: limit)
    }

    func forecastDisplayItem(for taskID: UUID) -> ForecastDisplayItem? {
        forecastDisplayService.displayItem(for: taskID, tasks: tasks, rollups: rollupDomainStore.taskRollups)
    }

    func rebuildChecklistIndexes() {
        checklistByTaskID = Dictionary(grouping: checklistItems.filter { $0.deletedAt == nil }, by: \.taskID)
            .mapValues { items in
                items.sorted { lhs, rhs in
                    if lhs.sortOrder == rhs.sortOrder {
                        return lhs.createdAt < rhs.createdAt
                    }
                    return lhs.sortOrder < rhs.sortOrder
                }
            }
    }

    func rebuildChecklistVisualIndexes() {
        checklistVisualByItemID = checklistItemVisuals
            .filter { $0.deletedAt == nil }
            .sorted { lhs, rhs in lhs.updatedAt < rhs.updatedAt }
            .reduce(into: [:]) { result, visual in
                result[visual.checklistItemID] = visual
            }
    }
}
