import Foundation
import SwiftData

extension TimeTrackerStore {
    func captureAITaskWorkspaceBaseline() async throws
        -> AITaskAtomicMutationBaseline
    {
        try await StoreScopedAITaskAtomicMutationCoordinator(
            container: requireStoreContainer(),
            writeAuthorization: writeAuthorization
        ).captureBaseline()
    }

    func applyAITaskWorkspaceReview(
        _ draft: AITaskWorkspaceReviewDraft
    ) async -> AITaskWorkspaceApplyResult {
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
            let outcome = try await StoreScopedAITaskAtomicMutationCoordinator(
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
}
