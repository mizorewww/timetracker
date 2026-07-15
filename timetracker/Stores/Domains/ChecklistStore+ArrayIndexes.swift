import Foundation

extension ChecklistStore {
    func sortedItems(_ items: [ChecklistItem]) -> [ChecklistItem] {
        items.sorted(by: itemOrder)
    }

    func sortedVisuals(_ visuals: [ChecklistItemVisual]) -> [ChecklistItemVisual] {
        visuals.sorted(by: visualOrder)
    }

    func itemOrder(_ lhs: ChecklistItem, _ rhs: ChecklistItem) -> Bool {
        if lhs.taskID != rhs.taskID {
            return lhs.taskID.uuidString < rhs.taskID.uuidString
        }
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    func visualOrder(_ lhs: ChecklistItemVisual, _ rhs: ChecklistItemVisual) -> Bool {
        if lhs.checklistItemID != rhs.checklistItemID {
            return lhs.checklistItemID.uuidString < rhs.checklistItemID.uuidString
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    func canReuseItemArray(
        taskIDs: Set<UUID>,
        fetchedItems: [ChecklistItem]
    ) -> Bool {
        let fetchedByTaskID = Dictionary(grouping: fetchedItems, by: \.taskID)
        return taskIDs.allSatisfy { taskID in
            let existing = itemsByTaskID[taskID] ?? []
            let fetched = fetchedByTaskID[taskID] ?? []
            guard existing.count == fetched.count else { return false }
            return zip(existing, fetched).allSatisfy { current, replacement in
                current.id == replacement.id && current === replacement
            }
        }
    }

    func canReuseVisualArray(
        checklistItemIDs: Set<UUID>,
        fetchedVisuals: [ChecklistItemVisual]
    ) -> Bool {
        let fetchedByItemID = Dictionary(grouping: fetchedVisuals, by: \.checklistItemID)
        return checklistItemIDs.allSatisfy { itemID in
            let existing = (visualIDsByChecklistItemID[itemID] ?? [])
                .compactMap { id -> (index: Int, visual: ChecklistItemVisual)? in
                    guard let index = visualArrayIndexByID[id] else { return nil }
                    return (index, visuals[index])
                }
                .sorted { $0.index < $1.index }
                .map(\.visual)
            let fetched = fetchedByItemID[itemID] ?? []
            guard existing.count == fetched.count else { return false }
            return zip(existing, fetched).allSatisfy { current, replacement in
                current.id == replacement.id && current === replacement
            }
        }
    }

    mutating func removeItems(ids: Set<UUID>) {
        let indices = ids.compactMap { itemArrayIndexByID[$0] }.sorted(by: >)
        guard let firstChangedIndex = indices.last else { return }
        for index in indices {
            items.remove(at: index)
        }
        for id in ids {
            itemArrayIndexByID.removeValue(forKey: id)
        }
        reindexItems(from: firstChangedIndex)
    }

    mutating func insertItems(_ insertedItems: [ChecklistItem]) {
        for item in insertedItems {
            let index = itemInsertionIndex(for: item)
            items.insert(item, at: index)
            reindexItems(from: index)
        }
    }

    mutating func removeVisuals(ids: Set<UUID>) {
        let indices = ids.compactMap { visualArrayIndexByID[$0] }.sorted(by: >)
        guard let firstChangedIndex = indices.last else { return }
        for index in indices {
            visuals.remove(at: index)
        }
        for id in ids {
            visualArrayIndexByID.removeValue(forKey: id)
        }
        reindexVisuals(from: firstChangedIndex)
    }

    mutating func insertVisuals(_ insertedVisuals: [ChecklistItemVisual]) {
        for visual in insertedVisuals {
            let index = visualInsertionIndex(for: visual)
            visuals.insert(visual, at: index)
            reindexVisuals(from: index)
        }
    }

    mutating func reindexItems(from startIndex: Int) {
        guard startIndex < items.count else { return }
        for index in startIndex..<items.count {
            itemArrayIndexByID[items[index].id] = index
        }
    }

    mutating func reindexVisuals(from startIndex: Int) {
        guard startIndex < visuals.count else { return }
        for index in startIndex..<visuals.count {
            visualArrayIndexByID[visuals[index].id] = index
        }
    }

    func itemInsertionIndex(for item: ChecklistItem) -> Int {
        var lowerBound = items.startIndex
        var upperBound = items.endIndex
        while lowerBound < upperBound {
            let middle = lowerBound + items.distance(from: lowerBound, to: upperBound) / 2
            if itemOrder(items[middle], item) {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }

    func visualInsertionIndex(for visual: ChecklistItemVisual) -> Int {
        var lowerBound = visuals.startIndex
        var upperBound = visuals.endIndex
        while lowerBound < upperBound {
            let middle = lowerBound + visuals.distance(from: lowerBound, to: upperBound) / 2
            if visualOrder(visuals[middle], visual) {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }
}
