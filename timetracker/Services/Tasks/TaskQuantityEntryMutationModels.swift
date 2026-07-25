import Foundation

nonisolated struct TaskQuantityEntryRecordCommand:
    Equatable,
    Sendable
{
    let taskID: UUID
    let goalBaseline: TaskQuantityGoalMutationBaseline
    let amount: Int
    let recordedAt: Date
    let proposedEntryID: UUID
}

nonisolated struct TaskQuantityEntryUpdateCommand:
    Equatable,
    Sendable
{
    let entryBaseline: TaskQuantityEntryMutationBaseline
    let goalBaseline: TaskQuantityGoalMutationBaseline
    let amount: Int
    let recordedAt: Date
    let operationID: UUID
}

nonisolated struct TaskQuantityEntryDeleteCommand:
    Equatable,
    Sendable
{
    let entryBaseline: TaskQuantityEntryMutationBaseline
    let operationID: UUID
}

enum TaskQuantityEntryMutationError: LocalizedError, Equatable {
    case invalidAmount
    case invalidRecordedAt
    case taskUnavailable
    case recurrenceTemplateRequiresGeneratedTask
    case quantityGoalUnavailable
    case quantityGoalChanged
    case incompleteQuantityGraph
    case entryUnavailable
    case entryChanged

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            AppStrings.localized("task.quantity.entry.error.invalidAmount")
        case .invalidRecordedAt:
            AppStrings.localized("task.quantity.entry.error.invalidDate")
        case .taskUnavailable:
            AppStrings.localized("task.quantity.entry.error.taskUnavailable")
        case .recurrenceTemplateRequiresGeneratedTask:
            AppStrings.localized(
                "task.quantity.entry.error.recurrenceTemplate"
            )
        case .quantityGoalUnavailable:
            AppStrings.localized("task.quantity.entry.error.goalUnavailable")
        case .quantityGoalChanged:
            AppStrings.localized("task.quantity.entry.error.goalChanged")
        case .incompleteQuantityGraph:
            AppStrings.localized("task.quantity.error.incompleteGraph")
        case .entryUnavailable:
            AppStrings.localized("task.quantity.entry.error.unavailable")
        case .entryChanged:
            AppStrings.localized("task.quantity.entry.error.changed")
        }
    }
}

struct TaskQuantityEntryMutationOutcome: Equatable {
    let taskID: UUID
    let entryID: UUID
    let didMutate: Bool
    let affectedAncestorTaskIDs: Set<UUID>
    let progressSnapshot: TaskQuantityProgressSnapshot?

    var convergenceEvents: Set<StoreDomainEvent> {
        [
            .taskChanged(
                taskID: taskID,
                affectedAncestorIDs: affectedAncestorTaskIDs
            ),
        ]
    }

    var events: Set<StoreDomainEvent> {
        didMutate ? convergenceEvents : []
    }
}

enum TaskQuantityEntryMutationCheckpoint: Equatable {
    case entryInserted(UUID)
    case entryUpdated(UUID)
    case entryDeleted(UUID)
}
