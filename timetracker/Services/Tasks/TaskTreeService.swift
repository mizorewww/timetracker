import Foundation

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
        var breadcrumbAccumulatorByTaskID: [UUID: TaskBreadcrumbAccumulator] = [:]
        var breadcrumbByTaskID: [UUID: TaskBreadcrumbPresentation] = [:]
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

            let breadcrumbAccumulator: TaskBreadcrumbAccumulator
            if let parentID,
               let parentBreadcrumb = breadcrumbAccumulatorByTaskID[parentID] {
                breadcrumbAccumulator = parentBreadcrumb.appending(task.title)
            } else {
                breadcrumbAccumulator = .root(task.title)
            }
            breadcrumbAccumulatorByTaskID[task.id] = breadcrumbAccumulator
            breadcrumbByTaskID[task.id] = breadcrumbAccumulator.presentation
            pending.append(contentsOf: childrenByParentID[task.id] ?? [])
        }

        return TaskTreeIndexes(
            orderedTaskIDs: tasks.map(\.id),
            taskByID: taskByID,
            childrenByParentID: childrenByParentID,
            taskIDsToDisplayAsRoots: repairPlan.taskIDsToDisplayAsRoots,
            taskPathByID: pathCache,
            taskParentPathByID: parentPathCache,
            taskBreadcrumbByID: breadcrumbByTaskID
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
        let canonicalTasks = tasks.deduplicatedByID()
        let availabilityService = TaskTrackingAvailabilityService()
        let eligibility = availabilityService.eligibility(tasks: canonicalTasks)
        guard eligibility.visibleTaskIDs.contains(taskID),
              let task = canonicalTasks.first(where: { $0.id == taskID }) else { return false }
        let isChangingParent = task.parentID != newParentID
        guard isChangingParent else { return true }
        if availabilityService.parentChangeBlocker(for: task) != nil {
            return false
        }
        guard let newParentID else { return true }
        guard taskID != newParentID else { return false }
        guard eligibility.visibleTaskIDs.contains(newParentID),
              eligibility.trackableTaskIDs.contains(newParentID) else {
            return false
        }
        return !descendantIDs(of: taskID, tasks: canonicalTasks).contains(newParentID)
    }

    func validParentTasks(for taskID: UUID?, tasks: [TaskNode]) -> [TaskNode] {
        let canonicalTasks = tasks.deduplicatedByID()
        let eligibility = TaskTrackingAvailabilityService().eligibility(tasks: canonicalTasks)
        let eligibleParents = canonicalTasks.filter {
            eligibility.visibleTaskIDs.contains($0.id) &&
                eligibility.trackableTaskIDs.contains($0.id)
        }
        guard let taskID else {
            return eligibleParents
        }
        let invalidIDs = descendantIDs(of: taskID, tasks: canonicalTasks).union([taskID])
        return eligibleParents.filter { !invalidIDs.contains($0.id) }
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

private struct TaskBreadcrumbAccumulator {
    static let maximumExactComponentCount = 4

    let firstComponent: String
    let recentComponents: [String]
    let exactComponents: [String]?
    let componentCount: Int

    static func root(_ title: String) -> TaskBreadcrumbAccumulator {
        TaskBreadcrumbAccumulator(
            firstComponent: title,
            recentComponents: [title],
            exactComponents: [title],
            componentCount: 1
        )
    }

    func appending(_ component: String) -> TaskBreadcrumbAccumulator {
        let updatedExactComponents: [String]?
        if let exactComponents,
           exactComponents.count < Self.maximumExactComponentCount {
            updatedExactComponents = exactComponents + [component]
        } else {
            updatedExactComponents = nil
        }
        return TaskBreadcrumbAccumulator(
            firstComponent: firstComponent,
            recentComponents: Array((recentComponents + [component]).suffix(2)),
            exactComponents: updatedExactComponents,
            componentCount: componentCount + 1
        )
    }

    var presentation: TaskBreadcrumbPresentation {
        let visibleComponents = exactComponents ??
            [firstComponent, "…"] + recentComponents
        return TaskBreadcrumbPresentation(
            visibleComponents: visibleComponents,
            totalComponentCount: componentCount
        )
    }
}
