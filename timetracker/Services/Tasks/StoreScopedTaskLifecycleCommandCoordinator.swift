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

    func archive(taskID: UUID) throws -> TaskArchiveMutationOutcome {
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
            let hasCanonicalArchiveMarkers =
                task.archivedAt != nil &&
                task.statusRaw == LegacyTaskStatusRaw.archived
            guard hasCanonicalArchiveMarkers == false else {
                return TaskArchiveMutationOutcome(
                    taskID: taskID,
                    didMutate: false,
                    relatedTaskIDs: relatedTaskIDs
                )
            }

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
                throw TaskLifecycleMutationError.activeWorkMustStop
            }

            try TaskDraftCommandHandler().archive(
                taskID: taskID,
                repository: taskRepository
            )
            return TaskArchiveMutationOutcome(
                taskID: taskID,
                didMutate: true,
                relatedTaskIDs: relatedTaskIDs
            )
        }
    }

    func unarchive(taskID: UUID) throws -> TaskUnarchiveMutationOutcome {
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
            let relatedTaskIDs = Self.relatedTaskIDs(for: task, tasks: tasks)
            guard task.deletedAt == nil, task.isArchivedForLifecycle else {
                return TaskUnarchiveMutationOutcome(
                    taskID: taskID,
                    didMutate: false,
                    relatedTaskIDs: relatedTaskIDs
                )
            }
            let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
            let repairPlan = TaskHierarchyRepairPlan(canonicalTasks: tasks)
            guard TaskTrackingAvailabilityService().hasArchivedAncestor(
                of: task,
                taskByID: taskByID,
                taskIDsToDisplayAsRoots: repairPlan.taskIDsToDisplayAsRoots
            ) == false else {
                throw TaskLifecycleMutationError.archivedAncestorMustRestoreFirst
            }

            try TaskDraftCommandHandler().unarchive(
                taskID: taskID,
                repository: taskRepository
            )
            return TaskUnarchiveMutationOutcome(
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
