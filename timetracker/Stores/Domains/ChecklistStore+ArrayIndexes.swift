import Foundation

nonisolated enum SortedUUIDArrayIndex {
    static func buildIndex<Element: PersistentUUIDModel>(
        for elements: [Element]
    ) -> [UUID: Int] {
        Dictionary(uniqueKeysWithValues: elements.indices.map {
            (elements[$0].id, $0)
        })
    }

    static func insertionIndex<Element>(
        for element: Element,
        in elements: [Element],
        orderedBy precedes: (Element, Element) -> Bool
    ) -> Int {
        var lowerBound = elements.startIndex
        var upperBound = elements.endIndex
        while lowerBound < upperBound {
            let middle = lowerBound + elements.distance(from: lowerBound, to: upperBound) / 2
            if precedes(elements[middle], element) {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }

    static func reindex<Element: PersistentUUIDModel>(
        _ elements: [Element],
        indexByID: inout [UUID: Int],
        from startIndex: Int
    ) {
        guard startIndex < elements.count else { return }
        for index in startIndex ..< elements.count {
            indexByID[elements[index].id] = index
        }
    }

    static func remove<Element: PersistentUUIDModel>(
        ids: Set<UUID>,
        from elements: inout [Element],
        indexByID: inout [UUID: Int]
    ) {
        let indices = ids.compactMap { indexByID[$0] }.sorted(by: >)
        guard let firstChangedIndex = indices.last else { return }
        for index in indices {
            elements.remove(at: index)
        }
        for id in ids {
            indexByID.removeValue(forKey: id)
        }
        reindex(elements, indexByID: &indexByID, from: firstChangedIndex)
    }

    static func insert<Element: PersistentUUIDModel>(
        _ insertedElements: [Element],
        into elements: inout [Element],
        indexByID: inout [UUID: Int],
        orderedBy precedes: (Element, Element) -> Bool
    ) {
        for element in insertedElements {
            let index = insertionIndex(for: element, in: elements, orderedBy: precedes)
            elements.insert(element, at: index)
            reindex(elements, indexByID: &indexByID, from: index)
        }
    }
}

extension ChecklistStore {
    func sortedItems(_ items: [ChecklistItem]) -> [ChecklistItem] {
        items.sorted(by: itemOrder)
    }

    func sortedVisuals(_ visuals: [ChecklistItemVisual]) -> [ChecklistItemVisual] {
        visuals.sorted(by: visualOrder)
    }

    func itemOrder(_ lhs: ChecklistItem, _ rhs: ChecklistItem) -> Bool {
        if lhs.taskID != rhs.taskID {
            return lhs.taskID < rhs.taskID
        }
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id < rhs.id
    }

    func visualOrder(_ lhs: ChecklistItemVisual, _ rhs: ChecklistItemVisual) -> Bool {
        if lhs.checklistItemID != rhs.checklistItemID {
            return lhs.checklistItemID < rhs.checklistItemID
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.id < rhs.id
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
        SortedUUIDArrayIndex.remove(
            ids: ids,
            from: &items,
            indexByID: &itemArrayIndexByID
        )
    }

    mutating func insertItems(_ insertedItems: [ChecklistItem]) {
        SortedUUIDArrayIndex.insert(
            insertedItems,
            into: &items,
            indexByID: &itemArrayIndexByID,
            orderedBy: itemOrder
        )
    }

    mutating func removeVisuals(ids: Set<UUID>) {
        SortedUUIDArrayIndex.remove(
            ids: ids,
            from: &visuals,
            indexByID: &visualArrayIndexByID
        )
    }

    mutating func insertVisuals(_ insertedVisuals: [ChecklistItemVisual]) {
        SortedUUIDArrayIndex.insert(
            insertedVisuals,
            into: &visuals,
            indexByID: &visualArrayIndexByID,
            orderedBy: visualOrder
        )
    }
}
