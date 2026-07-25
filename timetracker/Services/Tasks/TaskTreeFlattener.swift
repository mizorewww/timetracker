import Foundation

enum TaskTreeFlattener {
    static func visibleRows(
        rootTasks: [TaskNode],
        children: (TaskNode) -> [TaskNode],
        expandedTaskIDs: Set<UUID>
    ) -> [TaskTreeRowModel] {
        var rows: [TaskTreeRowModel] = []
        var pending = rootTasks.reversed().map { (task: $0, depth: 0) }
        var visited = Set<UUID>()

        while let current = pending.popLast() {
            guard visited.insert(current.task.id).inserted else { continue }
            let task = current.task
            let childTasks = children(task)
            let isExpanded = expandedTaskIDs.contains(task.id)
            rows.append(
                TaskTreeRowModel(
                    taskID: task.id,
                    depth: current.depth,
                    childCount: childTasks.count,
                    isExpanded: isExpanded
                )
            )

            guard isExpanded else { continue }
            for child in childTasks.reversed() {
                pending.append((task: child, depth: current.depth + 1))
            }
        }
        return rows
    }

    static func rowProjection(
        rootTaskIDs: [UUID],
        childTaskIDsByParentID: [UUID?: [UUID]],
        expandedTaskIDs: Set<UUID>
    ) -> TaskTreeRowProjection {
        var rows: [TaskTreeRowModel] = []
        var pending = rootTaskIDs.reversed().map { (taskID: $0, depth: 0) }
        var visited = Set<UUID>()
        var childBucketLookupCount = 0

        while let current = pending.popLast() {
            guard visited.insert(current.taskID).inserted else { continue }
            childBucketLookupCount += 1
            let childTaskIDs = childTaskIDsByParentID[current.taskID] ?? []
            let isExpanded = expandedTaskIDs.contains(current.taskID)
            rows.append(
                TaskTreeRowModel(
                    taskID: current.taskID,
                    depth: current.depth,
                    childCount: childTaskIDs.count,
                    isExpanded: isExpanded
                )
            )

            guard isExpanded else { continue }
            for childTaskID in childTaskIDs.reversed() {
                pending.append((taskID: childTaskID, depth: current.depth + 1))
            }
        }

        return TaskTreeRowProjection(
            rows: rows,
            operationCounts: TaskTreeProjectionOperationCounts(
                visitedTaskCount: rows.count,
                childBucketLookupCount: childBucketLookupCount
            )
        )
    }
}
