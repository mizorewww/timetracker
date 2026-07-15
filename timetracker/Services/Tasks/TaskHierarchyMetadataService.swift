import Foundation

struct TaskHierarchyMetadata: Equatable {
    let parentID: UUID?
    let depth: Int
    let path: String

    static func canonicalPath(for taskID: UUID) -> String {
        "/\(taskID.uuidString)"
    }
}

struct TaskHierarchyMetadataService {
    func normalizedMetadata(tasks: [TaskNode]) -> [UUID: TaskHierarchyMetadata] {
        let tasks = tasks.deduplicatedByID().filter { $0.deletedAt == nil }
        let repairPlan = TaskHierarchyRepairPlan(tasks: tasks)
        let parentByTaskID = tasks.reduce(into: [UUID: UUID?]()) { result, task in
            result[task.id] = repairPlan.taskIDsToDisplayAsRoots.contains(task.id) ? nil : task.parentID
        }
        let childrenByParentID = Dictionary(grouping: tasks) { task in
            parentByTaskID[task.id] ?? nil
        }

        var result: [UUID: TaskHierarchyMetadata] = [:]
        var visited = Set<UUID>()
        var pending = (childrenByParentID[nil] ?? [])
            .map { (id: $0.id, task: $0) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { $0.task }
            .reversed()
            .map { (task: $0, depth: 0) }

        while let next = pending.popLast() {
            guard visited.insert(next.task.id).inserted else { continue }
            result[next.task.id] = TaskHierarchyMetadata(
                parentID: parentByTaskID[next.task.id] ?? nil,
                depth: next.depth,
                path: TaskHierarchyMetadata.canonicalPath(for: next.task.id)
            )
            let sortedChildren = (childrenByParentID[next.task.id] ?? [])
                .map { (id: $0.id, task: $0) }
                .sorted { $0.id.uuidString < $1.id.uuidString }
                .map { $0.task }
            for child in sortedChildren.reversed() {
                pending.append((task: child, depth: next.depth + 1))
            }
        }

        // Defensive fallback for malformed imported graphs. The repair plan should
        // make every component reachable, but never leave metadata unbounded if a
        // future schema introduces another invalid shape.
        let sortedTasks = tasks
            .map { (id: $0.id, task: $0) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { $0.task }
        for task in sortedTasks where result[task.id] == nil {
            result[task.id] = TaskHierarchyMetadata(
                parentID: nil,
                depth: 0,
                path: TaskHierarchyMetadata.canonicalPath(for: task.id)
            )
        }
        return result
    }
}
