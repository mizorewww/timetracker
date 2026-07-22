import Foundation

nonisolated enum AITaskPlanSaveResult: Equatable, Sendable {
    case saved(firstRootTaskID: UUID?, didCreate: Bool)
    case failed(message: String)
}

enum StoreScopedAITaskPlanMutationError: LocalizedError, Equatable {
    case identityConflict

    var errorDescription: String? {
        switch self {
        case .identityConflict:
            AppStrings.localized("settings.llm.taskPlan.error.identityConflict")
        }
    }
}

struct AITaskPlanMutationOutcome: Equatable {
    let createdCategoryIDs: [UUID]
    let createdTaskIDs: [UUID]
    let firstRootTaskID: UUID?
    let didCreate: Bool

    var events: Set<StoreDomainEvent> {
        guard didCreate else { return [] }
        return [
            .taskChanged(taskID: nil, affectedAncestorIDs: []),
            .checklistChanged(taskID: nil, affectedAncestorIDs: []),
        ]
    }
}

enum AITaskPlanMutationCheckpoint: Equatable {
    case categoryCreated(UUID)
    case taskCreated(UUID)
    case checklistSaved(taskID: UUID)
    case progress(
        taskID: UUID,
        checkpoint: TaskDraftMutationCheckpoint
    )
}
