import Foundation

struct ChecklistStore {
    private(set) var items: [ChecklistItem] = []
    private(set) var visuals: [ChecklistItemVisual] = []

    mutating func refresh(items: [ChecklistItem], visuals: [ChecklistItemVisual]) {
        self.items = sortedItems(items.deduplicatedByID())
        self.visuals = sortedVisuals(visuals.deduplicatedByID())
    }

    mutating func refreshTaskScoped(
        taskIDs: Set<UUID>,
        items fetchedItems: [ChecklistItem],
        visuals fetchedVisuals: [ChecklistItemVisual]
    ) {
        guard taskIDs.isEmpty == false else { return }

        let existingItemIDs = Set(items.filter { taskIDs.contains($0.taskID) }.map(\.id))
        let fetchedItemIDs = Set(fetchedItems.map(\.id))
        let replacedItemIDs = existingItemIDs.union(fetchedItemIDs)

        items = sortedItems(
            (items.filter { taskIDs.contains($0.taskID) == false } + fetchedItems).deduplicatedByID()
        )
        visuals = sortedVisuals(
            (visuals.filter { replacedItemIDs.contains($0.checklistItemID) == false } + fetchedVisuals).deduplicatedByID()
        )
    }

    private func sortedItems(_ items: [ChecklistItem]) -> [ChecklistItem] {
        items.sorted { lhs, rhs in
            if lhs.taskID != rhs.taskID {
                return lhs.taskID.uuidString < rhs.taskID.uuidString
            }
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func sortedVisuals(_ visuals: [ChecklistItemVisual]) -> [ChecklistItemVisual] {
        visuals.sorted { lhs, rhs in
            if lhs.checklistItemID != rhs.checklistItemID {
                return lhs.checklistItemID.uuidString < rhs.checklistItemID.uuidString
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }
}
