import Foundation
import SwiftData

extension StoreScopedTaskLifecycleCommandCoordinator {
    func restoreArchivedHierarchy(
        taskID: UUID
    ) throws -> TaskHierarchyRestoreMutationOutcome {
        try writeAuthorization.requireUserWritesAllowed()
        let scope = try TimerStoreScope(container: container)
        let transaction = StoreScopedTimerMutationTransaction(
            scope: scope,
            container: container
        )

        return try transaction.withFreshContext(author: .localMutation) { context in
            let repository = SwiftDataTaskRepository(
                context: context,
                deviceID: deviceID
            )
            let tasks = try repository.allNodes()
            let taskByID = Dictionary(
                uniqueKeysWithValues: tasks.map { ($0.id, $0) }
            )
            guard let sourceTask = taskByID[taskID] else {
                throw TaskLifecycleMutationError.taskNotFound
            }

            let hierarchy = try Self.recoveryHierarchy(
                from: sourceTask,
                taskByID: taskByID
            )
            let tasksToRestore = hierarchy.reversed().filter(
                \.isArchivedForLifecycle
            )
            var restoredTaskIDs = Set<UUID>()
            var relatedTaskIDs = Set<UUID>()
            for task in tasksToRestore {
                relatedTaskIDs.formUnion(
                    Self.relatedTaskIDs(for: task, tasks: tasks)
                )
                try TaskDraftCommandHandler().unarchive(
                    taskID: task.id,
                    repository: repository
                )
                restoredTaskIDs.insert(task.id)
            }
            return TaskHierarchyRestoreMutationOutcome(
                taskID: taskID,
                restoredTaskIDs: restoredTaskIDs,
                relatedTaskIDs: relatedTaskIDs
            )
        }
    }

    private static func recoveryHierarchy(
        from sourceTask: TaskNode,
        taskByID: [UUID: TaskNode]
    ) throws -> [TaskNode] {
        var hierarchy: [TaskNode] = []
        var visited = Set<UUID>()
        var current: TaskNode? = sourceTask
        while let task = current,
              visited.insert(task.id).inserted
        {
            hierarchy.append(task)
            guard let parentID = task.parentID else { break }
            guard let parent = taskByID[parentID] else {
                throw TaskLifecycleMutationError.parentUnavailable
            }
            current = parent
        }
        return hierarchy
    }
}
