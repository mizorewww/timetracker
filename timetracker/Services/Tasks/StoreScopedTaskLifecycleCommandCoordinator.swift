import Foundation
import SwiftData

enum TaskLifecycleMutationError: LocalizedError, Equatable {
    case taskNotFound
    case activeWorkMustStop(TaskStatus)

    var errorDescription: String? {
        switch self {
        case .taskNotFound:
            AppStrings.localized("systemAction.error.taskNotFound")
        case .activeWorkMustStop(let status):
            AppStrings.localized(
                status == .completed
                    ? "task.action.complete.stopFirst"
                    : "task.action.archive.stopFirst"
            )
        }
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

/// Serializes local task availability changes with every timer admission for
/// the same SwiftData store. The canonical subtree and active work set are
/// fetched only after the shared timer lock is held.
@MainActor
struct StoreScopedTaskLifecycleCommandCoordinator {
    let container: ModelContainer
    let writeAuthorization: StoreWriteAuthorization
    let deviceID: String?

    init(
        container: ModelContainer,
        writeAuthorization: StoreWriteAuthorization = .applicationState,
        deviceID: String? = nil
    ) {
        self.container = container
        self.writeAuthorization = writeAuthorization
        self.deviceID = deviceID
    }

    func setStatus(
        _ status: TaskStatus,
        taskID: UUID
    ) throws -> TaskStatusMutationOutcome {
        try writeAuthorization.requireUserWritesAllowed()
        let scope = try TimerStoreScope(container: container)
        let transaction = StoreScopedTimerMutationTransaction(
            scope: scope,
            container: container
        )

        return try transaction.withFreshContext { context in
            let taskRepository = SwiftDataTaskRepository(
                context: context,
                deviceID: deviceID
            )
            let tasks = try taskRepository.allNodes()
            guard let task = tasks.first(where: { $0.id == taskID }) else {
                throw TaskLifecycleMutationError.taskNotFound
            }

            let relatedTaskIDs = Self.relatedTaskIDs(
                for: task,
                tasks: tasks
            )
            guard task.status != status else {
                return TaskStatusMutationOutcome(
                    taskID: taskID,
                    didMutate: false,
                    relatedTaskIDs: relatedTaskIDs
                )
            }

            if status == .completed || status == .archived {
                let subtreeIDs = TaskTreeService()
                    .descendantIDs(of: taskID, tasks: tasks)
                    .union([taskID])
                let timeRepository = SwiftDataTimeTrackingRepository(
                    context: context,
                    deviceID: deviceID
                )
                let pomodoroRepository = SwiftDataPomodoroRepository(
                    context: context,
                    timeRepository: timeRepository,
                    deviceID: deviceID
                )
                let hasActiveSegment = try timeRepository.activeSegments()
                    .contains { subtreeIDs.contains($0.taskID) }
                let hasActivePomodoro = try pomodoroRepository.activeRuns()
                    .contains { subtreeIDs.contains($0.taskID) }
                guard hasActiveSegment == false, hasActivePomodoro == false else {
                    throw TaskLifecycleMutationError.activeWorkMustStop(status)
                }
            }

            try taskRepository.setTaskStatus(taskID: taskID, status: status)
            return TaskStatusMutationOutcome(
                taskID: taskID,
                didMutate: true,
                relatedTaskIDs: relatedTaskIDs
            )
        }
    }

    func delete(taskID: UUID) throws -> TaskDeletionMutationOutcome {
        try writeAuthorization.requireUserWritesAllowed()
        let scope = try TimerStoreScope(container: container)
        let transaction = StoreScopedTimerMutationTransaction(
            scope: scope,
            container: container
        )

        return try transaction.withFreshContext { context in
            let taskRepository = SwiftDataTaskRepository(
                context: context,
                deviceID: deviceID
            )
            let tasks = try taskRepository.allNodes()
            guard let task = tasks.first(where: { $0.id == taskID }) else {
                throw TaskLifecycleMutationError.taskNotFound
            }
            let deletedTaskIDs = TaskTreeService()
                .descendantIDs(of: taskID, tasks: tasks)
                .union([taskID])
            let relatedTaskIDs = Self.relatedTaskIDs(for: task, tasks: tasks)
            let timeRepository = SwiftDataTimeTrackingRepository(
                context: context,
                deviceID: deviceID
            )
            let pomodoroRepository = SwiftDataPomodoroRepository(
                context: context,
                timeRepository: timeRepository,
                deviceID: deviceID
            )
            let activeSegments = try timeRepository.activeSegments().filter {
                deletedTaskIDs.contains($0.taskID)
            }
            let activeRuns = try pomodoroRepository.activeRuns().filter {
                deletedTaskIDs.contains($0.taskID)
            }
            let stoppedSegments = activeSegments.map {
                TaskLifecycleSegmentSnapshot(
                    segmentID: $0.id,
                    sessionID: $0.sessionID,
                    taskID: $0.taskID,
                    isPomodoro: $0.source == .pomodoro
                )
            }
            let terminatedPomodoros = activeRuns.map {
                TaskLifecyclePomodoroSnapshot(
                    runID: $0.id,
                    sessionID: $0.sessionID,
                    taskID: $0.taskID
                )
            }

            try TaskDraftCommandHandler().softDelete(
                taskID: taskID,
                affectedTaskIDs: deletedTaskIDs,
                activeSegments: activeSegments,
                pomodoroRuns: activeRuns,
                taskRepository: taskRepository,
                timeRepository: timeRepository,
                pomodoroRepository: pomodoroRepository
            )
            return TaskDeletionMutationOutcome(
                taskID: taskID,
                deletedTaskIDs: deletedTaskIDs,
                relatedTaskIDs: relatedTaskIDs,
                stoppedSegments: stoppedSegments,
                terminatedPomodoros: terminatedPomodoros
            )
        }
    }

    private static func relatedTaskIDs(
        for task: TaskNode,
        tasks: [TaskNode]
    ) -> Set<UUID> {
        let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        var related = TaskTreeService()
            .descendantIDs(of: task.id, tasks: tasks)
            .union([task.id])
        var visited = Set<UUID>()
        var parentID = task.parentID
        while let currentID = parentID,
              visited.insert(currentID).inserted,
              let parent = taskByID[currentID] {
            related.insert(currentID)
            parentID = parent.parentID
        }
        return related
    }
}
