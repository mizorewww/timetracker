import Foundation
import SwiftData

extension TimeTrackerStore {
    @discardableResult
    func restoreArchivedHierarchyForRecovery(
        taskID: UUID
    ) -> Bool {
        let outcome = performStoreCommand(
            onError: { error in
                if error is TaskLifecycleMutationError {
                    try? self.refresh(plan: StoreRefreshPlan(scopes: [.tasks]))
                }
                self.errorMessage = error.localizedDescription
            },
            command: { container in
                try StoreScopedTaskLifecycleCommandCoordinator(
                    container: container,
                    writeAuthorization: writeAuthorization
                ).restoreArchivedHierarchy(taskID: taskID)
            },
            finish: { outcome in
                if outcome.didMutate {
                    finishStoreScopedMutation(events: outcome.events)
                } else {
                    try refresh(plan: StoreRefreshPlan(scopes: [.tasks]))
                }
            }
        )
        guard outcome != nil else { return false }
        guard isTaskDetailRouteValid(taskID) else {
            errorMessage = AppStrings.localized(
                "task.editor.recovery.restoreUnavailable"
            )
            return false
        }
        return true
    }
}
