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
