import Foundation
import SwiftData

extension TimeTrackerStore {
    @discardableResult
    func toggleChecklistItem(_ item: ChecklistItem) -> Bool {
        performStoreCommand(
            eventsForOutcome: { $0.events },
            onError: handleStoreScopedChecklistError
        ) { container in
            try StoreScopedChecklistCommandCoordinator(
                container: container,
                writeAuthorization: writeAuthorization
            ).setCompletion(
                baseline: ChecklistMutationBaseline(item: item),
                isCompleted: !item.isCompleted
            )
        } != nil
    }

    @discardableResult
    func addChecklistItem(taskID: UUID, title: String) -> Bool {
        performStoreCommand(
            eventsForOutcome: { $0.events },
            onError: handleStoreScopedChecklistError
        ) { container in
            try StoreScopedChecklistCommandCoordinator(
                container: container,
                writeAuthorization: writeAuthorization
            ).add(taskID: taskID, title: title)
        } != nil
    }

    @discardableResult
    func reorderChecklistItems(taskID: UUID, sourceOffsets: IndexSet, destination: Int) -> Bool {
        let orderedItems = checklistItems(for: taskID).sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted
            }
            if lhs.sortOrder == rhs.sortOrder {
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.sortOrder < rhs.sortOrder
        }
        guard let orderedIDs = checklistCommandHandler.reorderedIDs(
            items: orderedItems,
            sourceOffsets: sourceOffsets,
            destination: destination
        ) else {
            return false
        }

        return performStoreCommand(
            eventsForOutcome: { $0.events },
            onError: handleStoreScopedChecklistError
        ) { container in
            try StoreScopedChecklistCommandCoordinator(
                container: container,
                writeAuthorization: writeAuthorization
            ).reorder(
                baseline: ChecklistOrderMutationBaseline(
                    taskID: taskID,
                    items: orderedItems
                ),
                orderedItemIDs: orderedIDs
            )
        } != nil
    }

    private func handleStoreScopedChecklistError(_ error: Error) {
        if error is StoreScopedChecklistMutationError {
            do {
                try refresh(plan: StoreRefreshPlan(scopes: [.tasks, .checklist]))
            } catch {
                errorMessage = savedRefreshFailedMessage(error)
                return
            }
        }
        errorMessage = error.localizedDescription
    }
}
