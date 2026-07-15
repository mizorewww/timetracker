import Foundation

struct TaskTreeIndexes {
    let taskByID: [UUID: TaskNode]
    let childrenByParentID: [UUID?: [TaskNode]]
    let taskPathByID: [UUID: String]
    let taskParentPathByID: [UUID: String]
}

struct TaskHierarchyRepairPlan: Equatable {
    let cycleBreakerTaskIDs: Set<UUID>
    let taskIDsToDisplayAsRoots: Set<UUID>

    init(tasks: [TaskNode]) {
        let visibleTasks = tasks
            .deduplicatedByID()
            .filter { $0.deletedAt == nil }
        let taskByID = visibleTasks.latestByID()
        let missingParentTaskIDs = Set(
            visibleTasks.compactMap { task -> UUID? in
                guard let parentID = task.parentID else { return nil }
                return taskByID[parentID] == nil ? task.id : nil
            }
        )
        var cycleBreakers = Set<UUID>()
        var processed = Set<UUID>()

        for startID in taskByID.keys.sorted(by: { $0.uuidString < $1.uuidString }) where !processed.contains(startID) {
            var path: [UUID] = []
            var indexByID: [UUID: Int] = [:]
            var cursor: UUID? = startID

            while let currentID = cursor,
                  let current = taskByID[currentID],
                  !processed.contains(currentID) {
                if let cycleStart = indexByID[currentID] {
                    let cycle = path[cycleStart...]
                    if let breaker = cycle.min(by: { $0.uuidString < $1.uuidString }) {
                        cycleBreakers.insert(breaker)
                    }
                    break
                }
                indexByID[currentID] = path.count
                path.append(currentID)
                cursor = current.parentID
            }
            processed.formUnion(path)
        }

        cycleBreakerTaskIDs = cycleBreakers
        taskIDsToDisplayAsRoots = missingParentTaskIDs.union(cycleBreakers)
    }
}

struct TaskTreeService {
    static let maximumDisplayedPathComponents = 6

    func indexes(tasks: [TaskNode]) -> TaskTreeIndexes {
        let tasks = tasks.deduplicatedByID()
        let taskByID = tasks.latestByID()
        let repairPlan = TaskHierarchyRepairPlan(tasks: tasks)
        let effectiveParentIDByTaskID = tasks.reduce(into: [UUID: UUID?]()) { result, task in
            result[task.id] = repairPlan.taskIDsToDisplayAsRoots.contains(task.id) ? nil : task.parentID
        }

        var grouped: [UUID?: [TaskNode]] = [:]
        for task in tasks where task.deletedAt == nil {
            grouped[effectiveParentIDByTaskID[task.id] ?? nil, default: []].append(task)
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
        var pathWasTruncatedByTaskID: [UUID: Bool] = [:]
        var pending = childrenByParentID[nil] ?? []
        var cursor = 0
        var visited = Set<UUID>()

        while cursor < pending.count {
            let task = pending[cursor]
            cursor += 1
            guard visited.insert(task.id).inserted else { continue }

            let parentID = effectiveParentIDByTaskID[task.id] ?? nil
            let parentComponents = parentID.flatMap { componentCache[$0] } ?? []
            let inheritedTruncation = parentID.flatMap { pathWasTruncatedByTaskID[$0] } ?? false
            let unboundedComponents = parentComponents + [task.title]
            let wasTruncated = inheritedTruncation ||
                unboundedComponents.count > Self.maximumDisplayedPathComponents
            let components = Array(unboundedComponents.suffix(Self.maximumDisplayedPathComponents))
            componentCache[task.id] = components
            pathWasTruncatedByTaskID[task.id] = wasTruncated
            parentPathCache[task.id] = parentID.flatMap { pathCache[$0] } ?? ""
            pathCache[task.id] = Self.displayPath(components: components, wasTruncated: wasTruncated)
            pending.append(contentsOf: childrenByParentID[task.id] ?? [])
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
        var seen = visited
        var pending = [taskID]
        var result = Set<UUID>()

        while let currentID = pending.popLast() {
            guard seen.insert(currentID).inserted else { continue }
            result.insert(currentID)
            pending.append(contentsOf: (childrenByParentID[currentID] ?? []).map(\.id))
        }
        return result
    }

    func descendantIDs(of taskID: UUID, tasks: [TaskNode]) -> Set<UUID> {
        let visibleTasks = tasks.deduplicatedByID().filter { $0.deletedAt == nil }
        let childIDsByParentID = Dictionary(grouping: visibleTasks, by: \.parentID)
            .mapValues { $0.map(\.id) }
        var pending = childIDsByParentID[taskID] ?? []
        var descendants = Set<UUID>()
        while let candidateID = pending.popLast() {
            guard candidateID != taskID, descendants.insert(candidateID).inserted else { continue }
            pending.append(contentsOf: childIDsByParentID[candidateID] ?? [])
        }
        return descendants
    }

    func canMove(taskID: UUID, to newParentID: UUID?, tasks: [TaskNode]) -> Bool {
        guard let newParentID else { return true }
        guard taskID != newParentID else { return false }
        guard tasks.contains(where: { $0.id == newParentID && $0.deletedAt == nil }) else { return false }
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

    private static func displayPath(components: [String], wasTruncated: Bool) -> String {
        let path = components.joined(separator: " / ")
        return wasTruncated ? "… / \(path)" : path
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
                    hasChildren: !childTasks.isEmpty,
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
}

extension TaskTreeService {
    func categorySections(
        rootTasks: [TaskNode],
        categories: [TaskCategory],
        categoryIDByRootTaskID: [UUID: UUID]
    ) -> [TaskTreeCategorySectionModel] {
        let categories = categories.deduplicatedByID()
        let categoryByID = categories.visibleDeduplicatedByID().latestByID()
        let rootTasksByCategory = Dictionary(grouping: rootTasks) { task -> UUID? in
            guard let categoryID = categoryIDByRootTaskID[task.id], categoryByID[categoryID] != nil else { return nil }
            return categoryID
        }

        var sections: [TaskTreeCategorySectionModel] = []
        for category in categories where category.deletedAt == nil {
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
