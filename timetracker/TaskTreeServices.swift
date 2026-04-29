import Foundation
import SwiftData

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

struct LedgerSummaryService {
    private let aggregationService = TimeAggregationService()

    func totalSeconds(
        taskIDs: Set<UUID>,
        segments: [TimeSegment],
        mode: AggregationMode = .gross,
        now: Date = Date()
    ) -> Int {
        let filtered = segments.filter { taskIDs.contains($0.taskID) && $0.deletedAt == nil }
        return aggregationService.totalSeconds(segments: filtered, mode: mode, now: now)
    }

    func secondsInInterval(
        taskIDs: Set<UUID>,
        segments: [TimeSegment],
        interval: DateInterval,
        mode: AggregationMode = .gross,
        now: Date = Date()
    ) -> Int {
        let intervals = segments.compactMap { segment -> DateInterval? in
            guard taskIDs.contains(segment.taskID), segment.deletedAt == nil else { return nil }
            let end = segment.endedAt ?? now
            guard segment.startedAt < interval.end, end > interval.start else { return nil }
            let start = max(segment.startedAt, interval.start)
            let clippedEnd = min(end, interval.end)
            guard clippedEnd > start else { return nil }
            return DateInterval(start: start, end: clippedEnd)
        }

        switch mode {
        case .gross:
            return intervals.reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start)) }
        case .wallClock:
            return aggregationService.mergeOverlappingIntervals(intervals).reduce(0) {
                $0 + Int($1.end.timeIntervalSince($1.start))
            }
        }
    }
}

@MainActor
struct ChecklistDraftService {
    func save(
        drafts: [ChecklistEditorDraft],
        taskID: UUID,
        context: ModelContext,
        deviceID: String = DeviceIdentity.current
    ) throws {
        let targetTaskID = taskID
        let existing = try context.fetch(
            FetchDescriptor<ChecklistItem>(
                predicate: #Predicate { $0.taskID == targetTaskID },
                sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
            )
        )
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        var keptIDs = Set<UUID>()

        for (index, draft) in drafts.enumerated() {
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            let sortOrder = Double(index + 1) * 10
            if let existingID = draft.existingID, let item = existingByID[existingID] {
                item.title = title
                if item.isCompleted != draft.isCompleted {
                    item.completedAt = draft.isCompleted ? Date() : nil
                }
                item.isCompleted = draft.isCompleted
                item.sortOrder = sortOrder
                item.deletedAt = nil
                item.updatedAt = Date()
                item.clientMutationID = UUID()
                keptIDs.insert(item.id)
            } else {
                let item = ChecklistItem(
                    taskID: taskID,
                    title: title,
                    isCompleted: draft.isCompleted,
                    sortOrder: sortOrder,
                    deviceID: deviceID
                )
                context.insert(item)
                keptIDs.insert(item.id)
            }
        }

        for item in existing where item.deletedAt == nil && !keptIDs.contains(item.id) {
            item.deletedAt = Date()
            item.updatedAt = Date()
            item.clientMutationID = UUID()
        }
        try context.save()
    }
}
