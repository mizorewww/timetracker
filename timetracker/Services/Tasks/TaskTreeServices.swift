import Foundation

struct TaskTreeIndexes {
    static let empty = TaskTreeIndexes(
        orderedTaskIDs: [],
        taskByID: [:],
        childrenByParentID: [:],
        taskPathByID: [:],
        taskParentPathByID: [:]
    )

    let orderedTaskIDs: [UUID]
    let taskByID: [UUID: TaskNode]
    let childrenByParentID: [UUID?: [TaskNode]]
    let taskPathByID: [UUID: String]
    let taskParentPathByID: [UUID: String]
}

struct TaskTreeSectionIndex: Identifiable, Equatable {
    let id: String
    let categoryID: UUID?
    let title: String
    let iconName: String
    let colorHex: String?
    let includesInForecast: Bool
    let rootTaskIDs: [UUID]
}

struct TaskTreeSearchEntry: Equatable {
    let taskID: UUID
    let title: String
    let path: String
    let notes: String?

    func matches(_ query: String) -> Bool {
        title.localizedCaseInsensitiveContains(query) ||
            path.localizedCaseInsensitiveContains(query) ||
            (notes?.localizedCaseInsensitiveContains(query) ?? false)
    }
}

/// Immutable hierarchy facts rebuilt by `TimeTrackerStore` only when task or
/// category mutations change their semantic value. SwiftUI projections consume
/// IDs and value types from this index; they never sort, filter children, or
/// walk ancestor title paths in a row body.
struct TaskTreeReadIndex: Equatable {
    static let empty = TaskTreeReadIndex(
        visibleChildIDsByParentID: [:],
        sections: [],
        searchEntries: []
    )

    let visibleChildIDsByParentID: [UUID?: [UUID]]
    let sections: [TaskTreeSectionIndex]
    let searchEntries: [TaskTreeSearchEntry]

    var rootTaskIDs: [UUID] {
        visibleChildIDsByParentID[nil] ?? []
    }

    var visibleTaskCount: Int {
        searchEntries.count
    }

    func visibleChildCount(for taskID: UUID) -> Int {
        visibleChildIDsByParentID[taskID]?.count ?? 0
    }

    func projection(expandedTaskIDs: Set<UUID>) -> TaskTreeProjection {
        var visibleSections: [TaskTreeVisibleSectionModel] = []
        visibleSections.reserveCapacity(sections.count)
        var visitedTaskCount = 0
        var childBucketLookupCount = 0

        for section in sections {
            let rowProjection = TaskTreeFlattener.rowProjection(
                rootTaskIDs: section.rootTaskIDs,
                childTaskIDsByParentID: visibleChildIDsByParentID,
                expandedTaskIDs: expandedTaskIDs
            )
            visitedTaskCount += rowProjection.operationCounts.visitedTaskCount
            childBucketLookupCount += rowProjection.operationCounts.childBucketLookupCount
            visibleSections.append(
                TaskTreeVisibleSectionModel(
                    id: section.id,
                    categoryID: section.categoryID,
                    title: section.title,
                    iconName: section.iconName,
                    colorHex: section.colorHex,
                    includesInForecast: section.includesInForecast,
                    rows: rowProjection.rows
                )
            )
        }

        return TaskTreeProjection(
            sections: visibleSections,
            operationCounts: TaskTreeProjectionOperationCounts(
                visitedTaskCount: visitedTaskCount,
                childBucketLookupCount: childBucketLookupCount
            )
        )
    }

    func searchProjection(matching query: String) -> TaskTreeSearchProjection {
        var matchingTaskIDs: [UUID] = []
        matchingTaskIDs.reserveCapacity(Swift.min(searchEntries.count, 16))
        for entry in searchEntries where entry.matches(query) {
            matchingTaskIDs.append(entry.taskID)
        }
        return TaskTreeSearchProjection(
            taskIDs: matchingTaskIDs,
            inspectedTaskCount: searchEntries.count
        )
    }
}

struct TaskTreeProjectionOperationCounts: Equatable {
    let visitedTaskCount: Int
    let childBucketLookupCount: Int
}

struct TaskTreeRowProjection: Equatable {
    let rows: [TaskTreeRowModel]
    let operationCounts: TaskTreeProjectionOperationCounts
}

struct TaskTreeProjection: Equatable {
    let sections: [TaskTreeVisibleSectionModel]
    let operationCounts: TaskTreeProjectionOperationCounts
}

struct TaskTreeSearchProjection: Equatable {
    let taskIDs: [UUID]
    let inspectedTaskCount: Int
}

/// Small revision-aware read-through cache shared by the task management and
/// sidebar projections. It retains IDs/value models only and bounds each LRU so
/// a long sequence of expansion states or search queries cannot grow memory.
struct TaskTreeProjectionCache {
    private struct HierarchyEntry {
        let expandedTaskIDs: Set<UUID>
        let projection: TaskTreeProjection
    }

    private struct SearchEntry {
        let query: String
        let projection: TaskTreeSearchProjection
    }

    private let capacity: Int
    private var revision: UInt64?
    private var hierarchyEntries: [HierarchyEntry] = []
    private var searchEntries: [SearchEntry] = []

    private(set) var hierarchyBuildCount = 0
    private(set) var searchBuildCount = 0
    private(set) var invalidationCount = 0

    init(capacity: Int = 4) {
        self.capacity = Swift.max(1, capacity)
    }

    var hierarchyEntryCount: Int {
        hierarchyEntries.count
    }

    var searchEntryCount: Int {
        searchEntries.count
    }

    mutating func projection(
        readIndex: TaskTreeReadIndex,
        revision: UInt64,
        expandedTaskIDs: Set<UUID>
    ) -> TaskTreeProjection {
        prepare(for: revision)
        if let index = hierarchyEntries.firstIndex(where: { $0.expandedTaskIDs == expandedTaskIDs }) {
            let entry = hierarchyEntries.remove(at: index)
            hierarchyEntries.append(entry)
            return entry.projection
        }

        let projection = readIndex.projection(expandedTaskIDs: expandedTaskIDs)
        hierarchyBuildCount += 1
        hierarchyEntries.append(
            HierarchyEntry(expandedTaskIDs: expandedTaskIDs, projection: projection)
        )
        if hierarchyEntries.count > capacity {
            hierarchyEntries.removeFirst(hierarchyEntries.count - capacity)
        }
        return projection
    }

    mutating func searchProjection(
        readIndex: TaskTreeReadIndex,
        revision: UInt64,
        query: String
    ) -> TaskTreeSearchProjection {
        prepare(for: revision)
        if let index = searchEntries.firstIndex(where: { $0.query == query }) {
            let entry = searchEntries.remove(at: index)
            searchEntries.append(entry)
            return entry.projection
        }

        let projection = readIndex.searchProjection(matching: query)
        searchBuildCount += 1
        searchEntries.append(SearchEntry(query: query, projection: projection))
        if searchEntries.count > capacity {
            searchEntries.removeFirst(searchEntries.count - capacity)
        }
        return projection
    }

    private mutating func prepare(for requestedRevision: UInt64) {
        guard revision != requestedRevision else { return }
        if revision != nil {
            invalidationCount += 1
        }
        revision = requestedRevision
        hierarchyEntries.removeAll(keepingCapacity: true)
        searchEntries.removeAll(keepingCapacity: true)
    }
}

struct TaskHierarchyRepairPlan: Equatable {
    let cycleBreakerTaskIDs: Set<UUID>
    let taskIDsToDisplayAsRoots: Set<UUID>

    init(tasks: [TaskNode]) {
        self.init(canonicalTasks: tasks.deduplicatedByID())
    }

    init(canonicalTasks: [TaskNode]) {
        let visibleTasks = canonicalTasks.filter { $0.deletedAt == nil }
        let taskByID = visibleTasks.reduce(into: [UUID: TaskNode]()) { result, task in
            result[task.id] = task
        }
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
        let taskByID = tasks.reduce(into: [UUID: TaskNode]()) { result, task in
            result[task.id] = task
        }
        let repairPlan = TaskHierarchyRepairPlan(canonicalTasks: tasks)
        let effectiveParentIDByTaskID = tasks.reduce(into: [UUID: UUID?]()) { result, task in
            result[task.id] = repairPlan.taskIDsToDisplayAsRoots.contains(task.id) ? nil : task.parentID
        }

        var grouped: [UUID?: [TaskNode]] = [:]
        for task in tasks where task.deletedAt == nil {
            grouped[effectiveParentIDByTaskID[task.id] ?? nil, default: []].append(task)
        }

        let childrenByParentID = grouped.mapValues { children in
            children.sorted(by: Self.siblingDisplayOrder)
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
            orderedTaskIDs: tasks.map(\.id),
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
        let visibleTasks = tasks.visibleDeduplicatedByID()
        guard visibleTasks.contains(where: { $0.id == taskID }) else { return false }
        guard let newParentID else { return true }
        guard taskID != newParentID else { return false }
        guard visibleTasks.contains(where: { $0.id == newParentID }) else { return false }
        return !descendantIDs(of: taskID, tasks: visibleTasks).contains(newParentID)
    }

    func validParentTasks(for taskID: UUID?, tasks: [TaskNode]) -> [TaskNode] {
        let visibleTasks = tasks.visibleDeduplicatedByID()
        guard let taskID else {
            return visibleTasks
        }
        let invalidIDs = descendantIDs(of: taskID, tasks: visibleTasks).union([taskID])
        return visibleTasks.filter { !invalidIDs.contains($0.id) }
    }

    private static func displayPath(components: [String], wasTruncated: Bool) -> String {
        let path = components.joined(separator: " / ")
        return wasTruncated ? "… / \(path)" : path
    }

    nonisolated private static func siblingDisplayOrder(_ lhs: TaskNode, _ rhs: TaskNode) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
        if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

struct TaskTreeRowModel: Identifiable, Equatable {
    let taskID: UUID
    let depth: Int
    let childCount: Int
    let isExpanded: Bool

    var id: UUID { taskID }
    var hasChildren: Bool { childCount > 0 }
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

struct TaskTreeVisibleSectionModel: Identifiable, Equatable {
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

extension TaskTreeService {
    func readIndex(
        indexes: TaskTreeIndexes,
        visibleTaskIDs: Set<UUID>,
        categories: [TaskCategory],
        categoryIDByRootTaskID: [UUID: UUID]
    ) -> TaskTreeReadIndex {
        var visibleChildIDsByParentID: [UUID?: [UUID]] = [:]
        for (parentID, children) in indexes.childrenByParentID {
            let childIDs = children.compactMap { task in
                visibleTaskIDs.contains(task.id) ? task.id : nil
            }
            if parentID == nil || !childIDs.isEmpty {
                visibleChildIDsByParentID[parentID] = childIDs
            }
        }

        let rootTasks = (visibleChildIDsByParentID[nil] ?? []).compactMap { indexes.taskByID[$0] }
        let sectionIndexes = categorySections(
            rootTasks: rootTasks,
            categories: categories,
            categoryIDByRootTaskID: categoryIDByRootTaskID
        ).map { section in
            TaskTreeSectionIndex(
                id: section.id,
                categoryID: section.categoryID,
                title: section.title,
                iconName: section.iconName,
                colorHex: section.colorHex,
                includesInForecast: section.includesInForecast,
                rootTaskIDs: section.rootTasks.map(\.id)
            )
        }

        let searchEntries = indexes.orderedTaskIDs.compactMap { taskID -> TaskTreeSearchEntry? in
            guard visibleTaskIDs.contains(taskID),
                  let task = indexes.taskByID[taskID],
                  task.deletedAt == nil else {
                return nil
            }
            return TaskTreeSearchEntry(
                taskID: taskID,
                title: task.title,
                path: indexes.taskPathByID[taskID] ?? task.title,
                notes: task.notes
            )
        }

        return TaskTreeReadIndex(
            visibleChildIDsByParentID: visibleChildIDsByParentID,
            sections: sectionIndexes,
            searchEntries: searchEntries
        )
    }

    func categorySections(
        rootTasks: [TaskNode],
        categories: [TaskCategory],
        categoryIDByRootTaskID: [UUID: UUID]
    ) -> [TaskTreeCategorySectionModel] {
        let categories = categories.deduplicatedByID()
        let categoryByID = categories.reduce(into: [UUID: TaskCategory]()) { result, category in
            guard category.deletedAt == nil else { return }
            result[category.id] = category
        }
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
