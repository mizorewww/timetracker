import Foundation

extension TimeTrackerStore {
    var recentTasks: [TaskNode] {
        tasks.filter { $0.status == .active }.prefix(4).map { $0 }
    }

    func frequentRecentTasks(excluding excludedIDs: Set<UUID> = [], limit: Int = 3) -> [TaskNode] {
        guard limit > 0 else { return [] }

        let availableTasks = tasks.filter {
            $0.deletedAt == nil &&
            $0.status != .archived &&
            !excludedIDs.contains($0.id)
        }
        let availableIDs = Set(availableTasks.map(\.id))
        let segmentsByTaskID = Dictionary(grouping: allSegments.filter {
            $0.deletedAt == nil && availableIDs.contains($0.taskID)
        }, by: \.taskID)

        let rankedTasks = availableTasks.compactMap { task -> (task: TaskNode, count: Int, lastStartedAt: Date)? in
            guard let segments = segmentsByTaskID[task.id], !segments.isEmpty else { return nil }
            let lastStartedAt = segments.map(\.startedAt).max() ?? task.updatedAt
            return (task, segments.count, lastStartedAt)
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            return lhs.lastStartedAt > rhs.lastStartedAt
        }
        .map(\.task)

        let rankedIDs = Set(rankedTasks.map(\.id))
        let fallbackTasks = recentTasks.filter {
            !excludedIDs.contains($0.id) && !rankedIDs.contains($0.id)
        }

        return Array((rankedTasks + fallbackTasks).prefix(limit))
    }

    var archivedTasks: [TaskNode] {
        tasks.filter { $0.status == .archived }
    }

    func task(for id: UUID) -> TaskNode? {
        taskByID[id]
    }

    func rootTasks() -> [TaskNode] {
        childrenByParentID[nil] ?? []
    }

    func taskCategory(for id: UUID?) -> TaskCategory? {
        guard let id else { return nil }
        return taskCategoryByID[id]
    }

    func rootTask(for task: TaskNode) -> TaskNode {
        var cursor = task
        var visited: Set<UUID> = [task.id]
        while let parentID = cursor.parentID,
              !visited.contains(parentID),
              let parent = taskByID[parentID] {
            visited.insert(parentID)
            cursor = parent
        }
        return cursor
    }

    func effectiveCategory(for task: TaskNode) -> TaskCategory? {
        let root = rootTask(for: task)
        return taskCategory(for: taskCategoryIDByRootTaskID[root.id])
    }

    func children(of task: TaskNode) -> [TaskNode] {
        childrenByParentID[task.id] ?? []
    }

    func validParentTasks(for taskID: UUID?) -> [TaskNode] {
        taskTreeService.validParentTasks(for: taskID, tasks: tasks)
    }

    func taskTreeRows(expandedTaskIDs: Set<UUID>) -> [TaskTreeRowModel] {
        TaskTreeFlattener.visibleRows(
            rootTasks: rootTasks(),
            children: { [weak self] task in
                self?.children(of: task) ?? []
            },
            expandedTaskIDs: expandedTaskIDs
        )
    }

    func taskTreeSections(expandedTaskIDs: Set<UUID>) -> [TaskTreeVisibleSectionModel] {
        taskTreeService.categorySections(
            rootTasks: rootTasks(),
            categories: taskCategories,
            categoryIDByRootTaskID: taskCategoryIDByRootTaskID
        ).map { section in
            TaskTreeVisibleSectionModel(
                id: section.id,
                categoryID: section.categoryID,
                title: section.title,
                iconName: section.iconName,
                colorHex: section.colorHex,
                includesInForecast: section.includesInForecast,
                rows: TaskTreeFlattener.visibleRows(
                    rootTasks: section.rootTasks,
                    children: { [weak self] task in
                        self?.children(of: task) ?? []
                    },
                    expandedTaskIDs: expandedTaskIDs
                )
            )
        }
    }

    func path(for task: TaskNode) -> String {
        taskPathByID[task.id] ?? task.title
    }

    func taskPath(for task: TaskNode) -> String {
        taskPathByID[task.id] ?? task.title
    }

    func rebuildTaskIndexes() {
        let indexes = taskTreeService.indexes(tasks: tasks)
        taskByID = indexes.taskByID
        childrenByParentID = indexes.childrenByParentID
        taskPathByID = indexes.taskPathByID
        taskParentPathByID = indexes.taskParentPathByID
    }

    func rebuildTaskCategoryIndexes() {
        taskCategoryByID = Dictionary(uniqueKeysWithValues: taskCategories.filter { $0.deletedAt == nil }.map { ($0.id, $0) })
        taskCategoryIDByRootTaskID = taskCategoryAssignments
            .filter { $0.deletedAt == nil }
            .sorted { $0.updatedAt < $1.updatedAt }
            .reduce(into: [:]) { result, assignment in
                result[assignment.taskID] = assignment.categoryID
            }
    }

    func taskAndDescendantIDs(for taskID: UUID, visited: Set<UUID> = []) -> Set<UUID> {
        taskTreeService.taskAndDescendantIDs(for: taskID, childrenByParentID: childrenByParentID, visited: visited)
    }

    func forecastEligibleTaskIDs() -> Set<UUID> {
        rootTasks().reduce(into: Set<UUID>()) { result, root in
            let includesInForecast = taskCategory(for: taskCategoryIDByRootTaskID[root.id])?.includesInForecast ?? true
            guard includesInForecast else { return }
            result.formUnion(taskAndDescendantIDs(for: root.id))
        }
    }
}
