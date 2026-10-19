import Foundation
import SwiftData

extension TimeTrackerStore {
    func toggleChecklistItem(_ item: ChecklistItem) throws {
        try performStoreCommand(
            eventsForOutcome: { $0.events },
            onError: handleStoreScopedChecklistError
        ) { session in
            try StoreScopedChecklistCommandCoordinator(
                session: session
            ).setCompletion(
                taskID: item.taskID,
                itemID: item.id,
                isCompleted: !item.isCompleted
            )
        }
    }

    func addChecklistItem(taskID: UUID, title: String) throws {
        try performStoreCommand(
            eventsForOutcome: { $0.events },
            onError: handleStoreScopedChecklistError
        ) { session in
            try StoreScopedChecklistCommandCoordinator(
                session: session
            ).add(taskID: taskID, title: title)
        }
    }

    private func handleStoreScopedChecklistError(_ error: Error) {
        if error is StoreScopedChecklistMutationError {
            refreshLoggingFailure(plan: StoreRefreshPlan(scopes: [.tasks, .checklist]))
        }
    }
}
