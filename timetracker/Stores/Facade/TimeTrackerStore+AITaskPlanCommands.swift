import Foundation
import SwiftData

extension TimeTrackerStore {
    func saveAITaskPlan(_ draft: AITaskPlanDraft) -> AITaskPlanSaveResult {
        guard let modelContext else {
            let message = StoreError.notConfigured.localizedDescription
            errorMessage = message
            return .failed(message: message)
        }

        do {
            let outcome = try StoreScopedAITaskPlanCommandCoordinator(
                container: modelContext.container,
                writeAuthorization: writeAuthorization
            ).apply(draft)
            if outcome.didCreate {
                finishStoreScopedMutation(events: outcome.events)
            } else {
                try refresh(plan: StoreRefreshPlan(scopes: [.tasks, .checklist]))
            }
            selectedTaskID = outcome.firstRootTaskID
            tasksRoute = nil
            desktopDestination = .tasks
            return .saved(
                firstRootTaskID: outcome.firstRootTaskID,
                didCreate: outcome.didCreate
            )
        } catch {
            let message = error.localizedDescription
            errorMessage = message
            return .failed(message: message)
        }
    }
}
