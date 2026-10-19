import Foundation
import SwiftData

extension TimeTrackerStore {
    @discardableResult
    func toggleChecklistItem(_ item: ChecklistItem) -> Bool {
        performStoreCommand(
            eventsForOutcome: { $0.events },
            onError: handleStoreScopedChecklistError
        ) { session in
            try StoreScopedChecklistCommandCoordinator(
                session: session
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
        ) { session in
            try StoreScopedChecklistCommandCoordinator(
                session: session
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
