import Foundation

struct TaskStore {
    private(set) var tasks: [TaskNode] = []
    private(set) var categories: [TaskCategory] = []
    private(set) var categoryAssignments: [TaskCategoryAssignment] = []

    mutating func refresh(repository: TaskRepository) throws {
        tasks = try repository.allNodes()
        categories = try repository.categories()
        categoryAssignments = try repository.categoryAssignments()
    }

    mutating func refreshTaskScoped(taskIDs: Set<UUID>, repository: TaskRepository) throws {
        guard taskIDs.isEmpty == false else { return }
        let fetchedTasks = try repository.tasks(ids: taskIDs)
        let fetchedTaskIDs = Set(fetchedTasks.map(\.id))
        let missingTaskIDs = taskIDs.subtracting(fetchedTaskIDs)
        let removedTaskIDs = missingTaskIDs.reduce(into: Set<UUID>()) { result, taskID in
            result.formUnion(taskAndDescendantIDs(for: taskID))
        }
        let replacedTaskIDs = taskIDs.union(removedTaskIDs)

        tasks = sortedTasks(
            tasks.filter { replacedTaskIDs.contains($0.id) == false } + fetchedTasks
        )
        categories = try repository.categories()
        categoryAssignments = try repository.categoryAssignments()
    }

    private func taskAndDescendantIDs(for taskID: UUID, visited: Set<UUID> = []) -> Set<UUID> {
        guard !visited.contains(taskID) else { return [] }
        let nextVisited = visited.union([taskID])
        let childIDs = tasks
            .filter { $0.parentID == taskID }
            .reduce(into: Set<UUID>()) { result, child in
                result.formUnion(taskAndDescendantIDs(for: child.id, visited: nextVisited))
            }
        return childIDs.union([taskID])
    }

    private func sortedTasks(_ tasks: [TaskNode]) -> [TaskNode] {
        tasks.sorted { lhs, rhs in
            if lhs.depth != rhs.depth {
                return lhs.depth < rhs.depth
            }
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.createdAt < rhs.createdAt
        }
    }
}
