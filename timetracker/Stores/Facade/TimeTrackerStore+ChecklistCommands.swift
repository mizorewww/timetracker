import Foundation

extension TimeTrackerStore {
    func toggleChecklistItem(_ item: ChecklistItem) {
        perform(event: .checklistChanged(taskID: item.taskID, affectedAncestorIDs: affectedAncestorIDs(for: item.taskID))) {
            guard let modelContext else { throw StoreError.notConfigured }
            try checklistCommandHandler.toggle(item, context: modelContext)
        }
    }

    func addChecklistItem(taskID: UUID, title: String) {
        perform(event: .checklistChanged(taskID: taskID, affectedAncestorIDs: affectedAncestorIDs(for: taskID))) {
            guard let modelContext else { throw StoreError.notConfigured }
            try checklistCommandHandler.add(
                taskID: taskID,
                title: title,
                existingItems: checklistItems(for: taskID),
                context: modelContext
            )
        }
    }

    func reorderChecklistItems(taskID: UUID, sourceOffsets: IndexSet, destination: Int) {
        let orderedItems = checklistItems(for: taskID).sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted
            }
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.sortOrder < rhs.sortOrder
        }
        guard let orderedIDs = checklistCommandHandler.reorderedIDs(
            items: orderedItems,
            sourceOffsets: sourceOffsets,
            destination: destination
        ) else {
            return
        }

        perform(event: .checklistChanged(taskID: taskID, affectedAncestorIDs: affectedAncestorIDs(for: taskID))) {
            guard let modelContext else { throw StoreError.notConfigured }
            try checklistCommandHandler.reorder(
                taskID: taskID,
                orderedItemIDs: orderedIDs,
                context: modelContext
            )
        }
    }
}
