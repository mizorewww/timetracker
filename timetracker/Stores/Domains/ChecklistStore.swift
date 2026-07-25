import Foundation

struct ChecklistStore {
    var items: [ChecklistItem] = []
    var visuals: [ChecklistItemVisual] = []
    private(set) var isInitialized = false
    var itemsByTaskID: [UUID: [ChecklistItem]] = [:]
    var itemArrayIndexByID: [UUID: Int] = [:]
    var visualIDsByChecklistItemID: [UUID: Set<UUID>] = [:]
    var visualArrayIndexByID: [UUID: Int] = [:]
    var visualByChecklistItemID: [UUID: ChecklistItemVisual] = [:]

    mutating func refresh(items: [ChecklistItem], visuals: [ChecklistItemVisual]) {
        self.items = sortedItems(items.deduplicatedByID())
        self.visuals = sortedVisuals(visuals.deduplicatedByID())
        itemsByTaskID = Dictionary(grouping: self.items, by: \.taskID)
        itemArrayIndexByID = Dictionary(uniqueKeysWithValues: self.items.indices.map {
            (self.items[$0].id, $0)
        })
        visualIDsByChecklistItemID = Dictionary(grouping: self.visuals, by: \.checklistItemID)
            .mapValues { Set($0.map(\.id)) }
        visualArrayIndexByID = Dictionary(uniqueKeysWithValues: self.visuals.indices.map {
            (self.visuals[$0].id, $0)
        })
        visualByChecklistItemID = self.visuals.reduce(into: [:]) { result, visual in
            if result[visual.checklistItemID] == nil {
                result[visual.checklistItemID] = visual
            }
        }
        isInitialized = true
    }

    mutating func refreshTaskScoped(
        taskIDs: Set<UUID>,
        items fetchedItems: [ChecklistItem],
        visuals fetchedVisuals: [ChecklistItemVisual]
    ) {
        guard taskIDs.isEmpty == false else { return }

        let canonicalFetchedItems = sortedItems(
            fetchedItems.deduplicatedByID().filter { taskIDs.contains($0.taskID) }
        )
        let existingItemIDs = Set(taskIDs.flatMap { itemsByTaskID[$0] ?? [] }.map(\.id))
        let fetchedItemIDs = Set(canonicalFetchedItems.map(\.id))
        let replacedItemIDs = existingItemIDs.union(fetchedItemIDs)

        if !canReuseItemArray(taskIDs: taskIDs, fetchedItems: canonicalFetchedItems) {
            removeItems(ids: replacedItemIDs)
            insertItems(canonicalFetchedItems)
        }
        for taskID in taskIDs {
            let taskItems = canonicalFetchedItems.filter { $0.taskID == taskID }
            if taskItems.isEmpty {
                itemsByTaskID.removeValue(forKey: taskID)
            } else {
                itemsByTaskID[taskID] = taskItems
            }
        }

        let canonicalFetchedVisuals = sortedVisuals(
            fetchedVisuals.deduplicatedByID().filter {
                replacedItemIDs.contains($0.checklistItemID)
            }
        )
        let existingVisualIDs = replacedItemIDs.reduce(into: Set<UUID>()) { result, itemID in
            result.formUnion(visualIDsByChecklistItemID[itemID] ?? [])
        }
        if !canReuseVisualArray(
            checklistItemIDs: replacedItemIDs,
            fetchedVisuals: canonicalFetchedVisuals
        ) {
            removeVisuals(ids: existingVisualIDs.union(canonicalFetchedVisuals.map(\.id)))
            insertVisuals(canonicalFetchedVisuals)
        }
        for itemID in replacedItemIDs {
            visualIDsByChecklistItemID.removeValue(forKey: itemID)
            visualByChecklistItemID.removeValue(forKey: itemID)
        }
        for (itemID, itemVisuals) in Dictionary(grouping: canonicalFetchedVisuals, by: \.checklistItemID) {
            visualIDsByChecklistItemID[itemID] = Set(itemVisuals.map(\.id))
            visualByChecklistItemID[itemID] = itemVisuals.first
        }
        isInitialized = true
    }

    func items(for taskID: UUID) -> [ChecklistItem] {
        itemsByTaskID[taskID] ?? []
    }

    func visual(for checklistItemID: UUID) -> ChecklistItemVisual? {
        visualByChecklistItemID[checklistItemID]
    }
}
