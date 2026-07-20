import Foundation
import SwiftData

extension TimeTrackerStore {
    @discardableResult
    func restoreArchivedHierarchyForRecovery(
        taskID: UUID
    ) -> Bool {
        guard let modelContext else {
            errorMessage = StoreError.notConfigured.localizedDescription
            return false
        }
        do {
            let outcome = try StoreScopedTaskLifecycleCommandCoordinator(
                container: modelContext.container,
                writeAuthorization: writeAuthorization
            ).restoreArchivedHierarchy(taskID: taskID)
            if outcome.didMutate {
                finishStoreScopedMutation(events: outcome.events)
            } else {
                try refresh(plan: StoreRefreshPlan(scopes: [.tasks]))
            }
            guard isTaskDetailRouteValid(taskID) else {
                errorMessage = AppStrings.localized(
                    "task.editor.recovery.restoreUnavailable"
                )
                return false
            }
            return true
        } catch {
            if error is TaskLifecycleMutationError {
                try? refresh(plan: StoreRefreshPlan(scopes: [.tasks]))
            }
            errorMessage = error.localizedDescription
            return false
        }
    }
}
