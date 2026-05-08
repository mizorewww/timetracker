import Foundation

struct TaskTreeIndexes {
    let taskByID: [UUID: TaskNode]
    let childrenByParentID: [UUID?: [TaskNode]]
    let taskPathByID: [UUID: String]
    let taskParentPathByID: [UUID: String]
}

struct TaskTreeService {
    func indexes(tasks: [TaskNode]) -> TaskTreeIndexes {
        let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })

        var grouped: [UUID?: [TaskNode]] = [:]
        for task in tasks where task.deletedAt == nil {
            grouped[task.parentID, default: []].append(task)
        }

        let childrenByParentID = grouped.mapValues { children in
            children.sorted { first, second in
                if first.sortOrder == second.sortOrder {
                    return first.title.localizedStandardCompare(second.title) == .orderedAscending
                }
                return first.sortOrder < second.sortOrder
            }
        }

        var pathCache: [UUID: String] = [:]
        var parentPathCache: [UUID: String] = [:]
        var componentCache: [UUID: [String]] = [:]

        func pathComponents(for task: TaskNode, visited: Set<UUID> = []) -> [String] {
            if let cached = componentCache[task.id] {
                return cached
            }
            guard !visited.contains(task.id) else { return [task.title] }

            let components: [String]
            if let parentID = task.parentID, let parent = taskByID[parentID], parent.deletedAt == nil {
                components = pathComponents(for: parent, visited: visited.union([task.id])) + [task.title]
            } else {
                components = [task.title]
            }
            componentCache[task.id] = components
            return components
        }

        for task in tasks where task.deletedAt == nil {
            let components = pathComponents(for: task)
            pathCache[task.id] = components.joined(separator: " / ")
            parentPathCache[task.id] = components.dropLast().joined(separator: " / ")
        }

        return TaskTreeIndexes(
            taskByID: taskByID,
            childrenByParentID: childrenByParentID,
            taskPathByID: pathCache,
            taskParentPathByID: parentPathCache
        )
    }

    func taskAndDescendantIDs(
        for taskID: UUID,
        childrenByParentID: [UUID?: [TaskNode]],
        visited: Set<UUID> = []
    ) -> Set<UUID> {
        guard !visited.contains(taskID) else { return [] }
        let nextVisited = visited.union([taskID])
        let childIDs = (childrenByParentID[taskID] ?? []).reduce(into: Set<UUID>()) { result, child in
            result.formUnion(taskAndDescendantIDs(for: child.id, childrenByParentID: childrenByParentID, visited: nextVisited))
        }
        return childIDs.union([taskID])
    }

    func descendantIDs(of taskID: UUID, tasks: [TaskNode]) -> Set<UUID> {
        let childrenByParentID = indexes(tasks: tasks).childrenByParentID
        return taskAndDescendantIDs(for: taskID, childrenByParentID: childrenByParentID).subtracting([taskID])
    }

    func canMove(taskID: UUID, to newParentID: UUID?, tasks: [TaskNode]) -> Bool {
        guard let newParentID else { return true }
        guard taskID != newParentID else { return false }
        return !descendantIDs(of: taskID, tasks: tasks).contains(newParentID)
    }

    func validParentTasks(for taskID: UUID?, tasks: [TaskNode]) -> [TaskNode] {
        guard let taskID else {
            return tasks.filter { $0.deletedAt == nil }
        }
        let invalidIDs = descendantIDs(of: taskID, tasks: tasks).union([taskID])
        return tasks.filter { task in
            task.deletedAt == nil && !invalidIDs.contains(task.id)
        }
    }
}

struct TaskTreeRowModel: Identifiable, Equatable {
    let taskID: UUID
    let depth: Int
    let hasChildren: Bool
    let isExpanded: Bool

    var id: UUID { taskID }
}

struct TaskTreeCategorySectionModel: Identifiable {
    let id: String
    let categoryID: UUID?
    let title: String
    let iconName: String
    let colorHex: String?
    let includesInForecast: Bool
    let rootTasks: [TaskNode]
}

struct TaskTreeVisibleSectionModel: Identifiable {
    let id: String
    let categoryID: UUID?
    let title: String
    let iconName: String
    let colorHex: String?
    let includesInForecast: Bool
    let rows: [TaskTreeRowModel]
}

struct TaskExpansionState: Equatable {
    private(set) var expandedTaskIDs: Set<UUID> = []

    func contains(_ taskID: UUID) -> Bool {
        expandedTaskIDs.contains(taskID)
    }

    mutating func toggle(_ taskID: UUID) {
        if expandedTaskIDs.contains(taskID) {
            expandedTaskIDs.remove(taskID)
        } else {
            expandedTaskIDs.insert(taskID)
        }
    }

    mutating func expand(_ taskID: UUID) {
        expandedTaskIDs.insert(taskID)
    }

    mutating func collapse(_ taskID: UUID) {
        expandedTaskIDs.remove(taskID)
    }
}

struct TaskTreeFlattener {
    static func visibleRows(
        rootTasks: [TaskNode],
        children: (TaskNode) -> [TaskNode],
        expandedTaskIDs: Set<UUID>
    ) -> [TaskTreeRowModel] {
        var rows: [TaskTreeRowModel] = []

        func append(_ task: TaskNode, depth: Int) {
            let childTasks = children(task)
            let isExpanded = expandedTaskIDs.contains(task.id)
            rows.append(
                TaskTreeRowModel(
                    taskID: task.id,
                    depth: depth,
                    hasChildren: !childTasks.isEmpty,
                    isExpanded: isExpanded
                )
            )

            guard isExpanded else { return }
            for child in childTasks {
                append(child, depth: depth + 1)
            }
        }

        for task in rootTasks {
            append(task, depth: 0)
        }
        return rows
    }
}

extension TaskTreeService {
    func categorySections(
        rootTasks: [TaskNode],
        categories: [TaskCategory],
        categoryIDByRootTaskID: [UUID: UUID]
    ) -> [TaskTreeCategorySectionModel] {
        let categoryByID = Dictionary(uniqueKeysWithValues: categories.filter { $0.deletedAt == nil }.map { ($0.id, $0) })
        let rootTasksByCategory = Dictionary(grouping: rootTasks) { task -> UUID? in
            guard let categoryID = categoryIDByRootTaskID[task.id], categoryByID[categoryID] != nil else { return nil }
            return categoryID
        }

        var sections: [TaskTreeCategorySectionModel] = []
        for category in categories where rootTasksByCategory[category.id]?.isEmpty == false {
            sections.append(
                TaskTreeCategorySectionModel(
                    id: "category-\(category.id.uuidString)",
                    categoryID: category.id,
                    title: category.title,
                    iconName: category.iconName ?? "square.grid.2x2",
                    colorHex: category.colorHex,
                    includesInForecast: category.includesInForecast,
                    rootTasks: rootTasksByCategory[category.id] ?? []
                )
            )
        }

        if let uncategorized = rootTasksByCategory[nil], !uncategorized.isEmpty {
            sections.append(
                TaskTreeCategorySectionModel(
                    id: "uncategorized",
                    categoryID: nil,
                    title: AppStrings.localized("taskCategory.uncategorized"),
                    iconName: "tray",
                    colorHex: "8E8E93",
                    includesInForecast: true,
                    rootTasks: uncategorized
                )
            )
        }

        return sections
    }
}
