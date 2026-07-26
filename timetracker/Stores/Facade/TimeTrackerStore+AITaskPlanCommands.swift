import Foundation
import SwiftData

extension TimeTrackerStore {
    func captureAITaskWorkspaceBaseline() throws
        -> AITaskAtomicMutationBaseline
    {
        guard let modelContext else {
            throw StoreError.notConfigured
        }
        return try StoreScopedAITaskAtomicMutationCoordinator(
            container: modelContext.container,
            writeAuthorization: writeAuthorization
        ).captureBaseline()
    }

    func applyAITaskWorkspaceReview(
        _ draft: AITaskWorkspaceReviewDraft
    ) -> AITaskWorkspaceApplyResult {
        guard let modelContext else {
            let message = StoreError.notConfigured.localizedDescription
            errorMessage = message
            return .failed(message: message)
        }

        let firstCreatedRootTaskID = draft.plan.operations.compactMap {
            operation -> UUID? in
            guard case let .createTask(task) = operation,
                  task.parentID == nil
            else {
                return nil
            }
            return task.id
        }.first

        do {
            let outcome = try StoreScopedAITaskAtomicMutationCoordinator(
                container: modelContext.container,
                writeAuthorization: writeAuthorization
            ).apply(
                AITaskAtomicMutationPlan(
                    baseline: draft.baseline,
                    operations: draft.plan.operations
                )
            )
            if outcome.didMutate {
                finishStoreScopedMutation(events: outcome.events)
            } else {
                try refresh(
                    plan: StoreRefreshPlan(scopes: [.tasks, .checklist])
                )
            }
            if let firstCreatedRootTaskID {
                selectedTaskID = firstCreatedRootTaskID
                tasksRoute = nil
                desktopDestination = .tasks
            }
            return .applied(
                firstCreatedRootTaskID: firstCreatedRootTaskID
            )
        } catch AITaskAtomicMutationError.workspaceChanged {
            let message = AITaskAtomicMutationError.workspaceChanged
                .localizedDescription
            errorMessage = message
            return .workspaceChanged(message: message)
        } catch {
            let message = error.localizedDescription
            errorMessage = message
            return .failed(message: message)
        }
    }

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
