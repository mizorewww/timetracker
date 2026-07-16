import Foundation

enum TaskLifecycleMutationError: LocalizedError, Equatable {
    case taskNotFound
    case activeWorkMustStop(TaskStatus)
    case parentChangeBlocked(TaskParentChangeBlocker)
    case parentUnavailable
    case staleDraft

    var errorDescription: String? {
        switch self {
        case .taskNotFound:
            return AppStrings.localized("systemAction.error.taskNotFound")
        case .activeWorkMustStop(let status):
            return AppStrings.localized(
                status == .completed
                    ? "task.action.complete.stopFirst"
                    : "task.action.archive.stopFirst"
            )
        case .parentChangeBlocked(let blocker):
            let key = switch blocker {
            case .completed: "task.parent.completedLocked"
            case .archived: "task.parent.archivedLocked"
            case .deleted: "task.parent.deletedLocked"
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

    var events: Set<StoreDomainEvent> {
        [
            .taskChanged(
                taskID: savedTaskID,
                affectedAncestorIDs: relatedTaskIDs.subtracting([savedTaskID])
            ),
            .checklistChanged(
                taskID: savedTaskID,
                affectedAncestorIDs: checklistAncestorIDs
            ),
        ]
    }
}

struct TaskStatusMutationOutcome: Equatable {
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

struct TaskLifecyclePomodoroSnapshot: Equatable, Hashable {
    let runID: UUID
    let sessionID: UUID?
    let taskID: UUID
}

struct TaskLifecycleSegmentSnapshot: Equatable, Hashable {
    let segmentID: UUID
    let sessionID: UUID
    let taskID: UUID
    let isPomodoro: Bool
}

struct TaskDeletionMutationOutcome: Equatable {
    let taskID: UUID
    let deletedTaskIDs: Set<UUID>
    let relatedTaskIDs: Set<UUID>
    let stoppedSegments: [TaskLifecycleSegmentSnapshot]
    let terminatedPomodoros: [TaskLifecyclePomodoroSnapshot]

    var events: Set<StoreDomainEvent> {
        var events: Set<StoreDomainEvent> = [
            .taskChanged(
                taskID: taskID,
                affectedAncestorIDs: relatedTaskIDs.subtracting([taskID])
            ),
        ]
        let terminatedSessionIDs = Set(terminatedPomodoros.compactMap(\.sessionID))
        for segment in stoppedSegments {
            events.insert(
                .ledgerChanged(
                    taskID: segment.taskID,
                    dateInterval: nil,
                    isVisible: true
                )
            )
            if segment.isPomodoro,
               terminatedSessionIDs.contains(segment.sessionID) == false {
                events.insert(
                    .pomodoroChanged(
                        runID: nil,
                        sessionID: segment.sessionID,
                        taskID: segment.taskID
                    )
                )
            }
        }
        for run in terminatedPomodoros {
            events.insert(
                .pomodoroChanged(
                    runID: run.runID,
                    sessionID: run.sessionID,
                    taskID: run.taskID
                )
            )
        }
        return events
    }
}
