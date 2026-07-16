import Foundation
import SwiftData

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

    func reopenForWork(taskID: UUID) throws -> TaskReopenMutationOutcome {
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
            guard tasks.contains(where: { $0.id == taskID }) else {
                throw TaskLifecycleMutationError.taskNotFound
            }

            let blockerIDs = TaskTrackingAvailabilityService()
                .completedBlockingTaskIDs(for: taskID, tasks: tasks)
            let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
            let mutations = blockerIDs.compactMap { blockerID -> TaskStatusMutationOutcome? in
                guard let blocker = taskByID[blockerID], blocker.status == .completed else {
                    return nil
                }
                return TaskStatusMutationOutcome(
                    taskID: blockerID,
                    didMutate: true,
                    relatedTaskIDs: Self.relatedTaskIDs(for: blocker, tasks: tasks)
                )
            }

            for mutation in mutations {
                try taskRepository.setTaskStatus(
                    taskID: mutation.taskID,
                    status: .active
                )
            }
            return TaskReopenMutationOutcome(
                requestedTaskID: taskID,
                reopenedTasks: mutations
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

    static func relatedTaskIDs(
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
