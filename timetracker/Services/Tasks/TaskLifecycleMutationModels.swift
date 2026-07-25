import Foundation

nonisolated enum TaskDraftSaveResult: Equatable, Sendable {
    case saved(taskID: UUID)
    case stale
    case failed(message: String)
}

enum TaskLifecycleMutationError: LocalizedError, Equatable {
    case taskNotFound
    case activeWorkMustStop
    case archivedAncestorMustRestoreFirst
    case parentChangeBlocked(TaskParentChangeBlocker)
    case parentUnavailable
    case staleDraft

    var errorDescription: String? {
        switch self {
        case .taskNotFound:
            return AppStrings.localized("systemAction.error.taskNotFound")
        case .activeWorkMustStop:
            return AppStrings.localized("task.action.archive.stopFirst")
        case .archivedAncestorMustRestoreFirst:
            return AppStrings.localized("task.action.unarchive.parentFirst")
        case let .parentChangeBlocked(blocker):
            let key = switch blocker {
            case .archived: "task.parent.archivedLocked"
            case .unavailable: "task.parent.unavailableLocked"
            }
            return AppStrings.localized(key)
        case .parentUnavailable:
            return AppStrings.localized("task.parentUnavailable")
        case .staleDraft:
            return AppStrings.localized("task.editor.staleDraft")
        }
    }
}

struct TaskDraftMutationOutcome: Equatable {
    let savedTaskID: UUID
    let relatedTaskIDs: Set<UUID>
    let checklistAncestorIDs: Set<UUID>
    let recurrenceOutcome: TaskRecurrenceMutationOutcome

    var events: Set<StoreDomainEvent> {
        Set<StoreDomainEvent>([
            .taskChanged(
                taskID: savedTaskID,
                affectedAncestorIDs: relatedTaskIDs.subtracting([savedTaskID])
            ),
            .checklistChanged(
                taskID: savedTaskID,
                affectedAncestorIDs: checklistAncestorIDs
            ),
        ]).union(recurrenceOutcome.events)
    }
}

enum TaskDraftMutationCheckpoint: Equatable {
    case taskAndChecklistSaved(UUID)
    case quantityGoalChanged(UUID)
    case recurrence(TaskRecurrenceMutationCheckpoint)
}

struct TaskArchiveMutationOutcome: Equatable {
    let taskID: UUID
    let didMutate: Bool
    let relatedTaskIDs: Set<UUID>

    var events: Set<StoreDomainEvent> {
        guard didMutate else { return [] }
        return [
            .taskChanged(
                taskID: taskID,
                affectedAncestorIDs: relatedTaskIDs.subtracting([taskID])
            ),
        ]
    }
}

struct TaskUnarchiveMutationOutcome: Equatable {
    let taskID: UUID
    let didMutate: Bool
    let relatedTaskIDs: Set<UUID>

    var events: Set<StoreDomainEvent> {
        guard didMutate else { return [] }
        return [
            .taskChanged(
                taskID: taskID,
                affectedAncestorIDs: relatedTaskIDs.subtracting([taskID])
            ),
        ]
    }
}

struct TaskHierarchyRestoreMutationOutcome: Equatable {
    let taskID: UUID
    let restoredTaskIDs: Set<UUID>
    let relatedTaskIDs: Set<UUID>

    var didMutate: Bool {
        restoredTaskIDs.isEmpty == false
    }

    var events: Set<StoreDomainEvent> {
        Set(restoredTaskIDs.map { restoredTaskID in
            .taskChanged(
                taskID: restoredTaskID,
                affectedAncestorIDs: relatedTaskIDs.subtracting(
                    [restoredTaskID]
                )
            )
        })
    }
}
