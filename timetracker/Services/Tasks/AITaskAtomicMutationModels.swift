import Foundation

nonisolated struct AITaskAtomicMutationBaseline: Equatable, Sendable {
    let snapshot: AITaskWorkspaceSnapshot
    let workspace: AITaskWorkspaceMutationBaselines
    let quantityGoalMutationIDs: [UUID: UUID]
    let recurrenceRuleMutationIDs: [UUID: UUID]
}

nonisolated struct AITaskAtomicMutationPlan: Equatable, Sendable {
    let baseline: AITaskAtomicMutationBaseline
    let operations: [AITaskWorkspaceOperation]
}

nonisolated struct AITaskWorkspaceReviewDraft: Equatable, Sendable {
    let baseline: AITaskAtomicMutationBaseline
    let plan: LLMTaskWorkspacePlan
}

nonisolated enum AITaskWorkspaceApplyResult: Equatable, Sendable {
    case applied(firstCreatedRootTaskID: UUID?)
    case workspaceChanged(message: String)
    case failed(message: String)
}

nonisolated enum AITaskAtomicMutationError:
    LocalizedError,
    Equatable,
    Sendable
{
    case workspaceChanged
    case invalidOperation
    case identityConflict(UUID)
    case protectedIdentity(UUID)
    case targetUnavailable(UUID)
    case activeWorkMustStop

    var errorDescription: String? {
        switch self {
        case .workspaceChanged:
            AppStrings.localized("aiTaskPlan.error.workspaceChanged")
        case .invalidOperation:
            AppStrings.localized("aiTaskPlan.error.invalidOperation")
        case .identityConflict:
            AppStrings.localized("aiTaskPlan.error.identityConflict")
        case .protectedIdentity:
            AppStrings.localized("aiTaskPlan.error.protectedIdentity")
        case .targetUnavailable:
            AppStrings.localized("aiTaskPlan.error.targetUnavailable")
        case .activeWorkMustStop:
            AppStrings.localized("aiTaskPlan.error.activeWork")
        }
    }
}

nonisolated enum AITaskAtomicMutationCheckpoint: Equatable, Sendable {
    case operationApplied(index: Int)
}

nonisolated struct AITaskAtomicMutationOutcome: Equatable, Sendable {
    let didMutate: Bool
    let didMutateTasks: Bool
    let didMutateChecklists: Bool

    var events: Set<StoreDomainEvent> {
        guard didMutate else { return [] }
        var result = Set<StoreDomainEvent>()
        if didMutateTasks {
            result.insert(
                .taskChanged(taskID: nil, affectedAncestorIDs: [])
            )
        }
        if didMutateChecklists {
            result.insert(
                .checklistChanged(taskID: nil, affectedAncestorIDs: [])
            )
        }
        return result
    }
}
