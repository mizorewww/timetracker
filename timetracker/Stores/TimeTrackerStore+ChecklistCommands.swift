import Foundation

extension TimeTrackerStore {
    func toggleChecklistItem(_ item: ChecklistItem) {
        perform(event: .checklistChanged(taskID: item.taskID)) {
            guard let modelContext else { throw StoreError.notConfigured }
            try checklistCommandHandler.toggle(item, context: modelContext)
        }
    }

    func addChecklistItem(taskID: UUID, title: String) {
        perform(event: .checklistChanged(taskID: taskID)) {
            guard let modelContext else { throw StoreError.notConfigured }
            try checklistCommandHandler.add(
                taskID: taskID,
                title: title,
                existingItems: checklistItems(for: taskID),
                context: modelContext
            )
        }
    }
}
