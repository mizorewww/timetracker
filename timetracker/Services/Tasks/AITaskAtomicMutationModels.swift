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

nonisolated enum AITaskAtomicMutationError: Error, Equatable, Sendable {
    case workspaceChanged
    case invalidOperation
    case identityConflict(UUID)
    case protectedIdentity(UUID)
    case targetUnavailable(UUID)
    case activeWorkMustStop
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
