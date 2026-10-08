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
