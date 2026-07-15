import Foundation

struct TaskStore {
    private(set) var tasks: [TaskNode] = []
    private(set) var categories: [TaskCategory] = []
    private(set) var categoryAssignments: [TaskCategoryAssignment] = []

    mutating func refresh(repository: TaskRepository) throws {
        tasks = try repository.allNodes().deduplicatedByID()
        categories = try repository.categories().deduplicatedByID()
        categoryAssignments = try repository.categoryAssignments().deduplicatedByID()
    }

    mutating func refreshTaskScoped(taskIDs: Set<UUID>, repository: TaskRepository) throws {
        guard taskIDs.isEmpty == false else { return }
        let fetchedTasks = try repository.tasks(ids: taskIDs).deduplicatedByID()
        let fetchedTaskIDs = Set(fetchedTasks.map(\.id))
        let missingTaskIDs = taskIDs.subtracting(fetchedTaskIDs)
        let childrenByParentID = Dictionary(grouping: tasks, by: \.parentID)
        let removedTaskIDs = taskAndDescendantIDs(
            for: missingTaskIDs,
            childrenByParentID: childrenByParentID
        )
        let replacedTaskIDs = taskIDs.union(removedTaskIDs)

        tasks = sortedTasks(
            (tasks.filter { replacedTaskIDs.contains($0.id) == false } + fetchedTasks).deduplicatedByID()
        )
        categories = try repository.categories().deduplicatedByID()
        categoryAssignments = try repository.categoryAssignments().deduplicatedByID()
    }

    private func taskAndDescendantIDs(
        for taskIDs: Set<UUID>,
        childrenByParentID: [UUID?: [TaskNode]]
    ) -> Set<UUID> {
        var result = Set<UUID>()
        var pending = Array(taskIDs)
        while let currentID = pending.popLast() {
            guard result.insert(currentID).inserted else { continue }
            pending.append(contentsOf: (childrenByParentID[currentID] ?? []).map(\.id))
        }
        return result
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
