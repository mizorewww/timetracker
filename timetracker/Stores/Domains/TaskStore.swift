import Foundation

struct TaskStore {
    private(set) var tasks: [TaskNode] = []
    private(set) var categories: [TaskCategory] = []
    private(set) var categoryAssignments: [TaskCategoryAssignment] = []
    private(set) var recurrenceRules: [TaskRecurrenceRule] = []
    private(set) var recurrenceOccurrences: [TaskRecurrenceOccurrence] = []
    private(set) var quantityGoals: [TaskQuantityGoal] = []
    private(set) var quantityEntries: [TaskQuantityEntry] = []
    private(set) var incompleteQuantityProgressTaskIDs = Set<UUID>()

    mutating func refresh(repository: TaskRepository) throws {
        tasks = try repository.allNodes().deduplicatedByID()
        categories = try repository.categories().deduplicatedByID()
        categoryAssignments = try repository.categoryAssignments().deduplicatedByID()
        try refreshAllTaskProgress(repository: repository)
    }

    mutating func refreshTaskScoped(taskIDs: Set<UUID>, repository: TaskRepository) throws {
        guard taskIDs.isEmpty == false else { return }
        var fetchedTasks = try repository.tasks(ids: taskIDs)
            .deduplicatedByID()
        let visibleScopeIDs = Set(fetchedTasks.map(\.id))
        let cachedRelatedTaskIDs = Set(
            recurrenceOccurrences.lazy.filter {
                visibleScopeIDs.contains($0.templateTaskID) ||
                    visibleScopeIDs.contains($0.generatedTaskID)
            }.map(\.generatedTaskID)
        )
        let fetchedRelatedTaskIDs = Set(
            try repository.taskRecurrenceOccurrences(
                taskIDs: visibleScopeIDs
            ).map(\.generatedTaskID)
        )
        let relatedTaskIDs = cachedRelatedTaskIDs.union(
            fetchedRelatedTaskIDs
        )
        fetchedTasks = (
            fetchedTasks + (try repository.tasks(ids: relatedTaskIDs))
        ).deduplicatedByID()
        let scopedTaskIDs = taskIDs.union(relatedTaskIDs)
        let fetchedTaskIDs = Set(fetchedTasks.map(\.id))
        let missingTaskIDs = scopedTaskIDs.subtracting(fetchedTaskIDs)
        let childrenByParentID = Dictionary(grouping: tasks, by: \.parentID)
        let removedTaskIDs = taskAndDescendantIDs(
            for: missingTaskIDs,
            childrenByParentID: childrenByParentID
        )
        let replacedTaskIDs = scopedTaskIDs.union(removedTaskIDs)

        tasks = sortedTasks(
            (tasks.filter { replacedTaskIDs.contains($0.id) == false } + fetchedTasks).deduplicatedByID()
        )
        categories = try repository.categories().deduplicatedByID()
        categoryAssignments = try repository.categoryAssignments().deduplicatedByID()
        try refreshTaskProgress(
            queryTaskIDs: scopedTaskIDs,
            replacingTaskIDs: replacedTaskIDs,
            repository: repository
        )
    }

    private mutating func refreshAllTaskProgress(
        repository: TaskRepository
    ) throws {
        recurrenceRules = try repository.taskRecurrenceRules()
            .deduplicatedByID()
        recurrenceOccurrences = try repository.taskRecurrenceOccurrences()
            .deduplicatedByID()
        quantityGoals = try repository.taskQuantityGoals()
            .deduplicatedByID()
        quantityEntries = try repository.taskQuantityEntries()
            .deduplicatedByID()
        hideIncompleteTaskProgressRelationships()
    }

    private mutating func refreshTaskProgress(
        queryTaskIDs: Set<UUID>,
        replacingTaskIDs: Set<UUID>,
        repository: TaskRepository
    ) throws {
        let fetchedRules = try repository.taskRecurrenceRules(
            taskIDs: queryTaskIDs
        )
        let fetchedOccurrences = try repository.taskRecurrenceOccurrences(
            taskIDs: queryTaskIDs
        )
        // Quantity records form one relational graph. A malformed entry can
        // connect otherwise unrelated tasks through a non-canonical goal ID,
        // so a task-scoped fetch cannot safely prove the graph complete.
        let fetchedGoals = try repository.taskQuantityGoals()
        let fetchedEntries = try repository.taskQuantityEntries()
        recurrenceRules = (
            recurrenceRules.filter {
                replacingTaskIDs.contains($0.templateTaskID) == false
            } +
            fetchedRules
        ).deduplicatedByID()
        recurrenceOccurrences = (
            recurrenceOccurrences.filter {
                replacingTaskIDs.contains($0.templateTaskID) == false &&
                    replacingTaskIDs.contains($0.generatedTaskID) == false
            } +
            fetchedOccurrences
        ).deduplicatedByID()
        quantityGoals = fetchedGoals.deduplicatedByID()
        quantityEntries = fetchedEntries.deduplicatedByID()
        hideIncompleteTaskProgressRelationships()
    }

    private mutating func hideIncompleteTaskProgressRelationships() {
        incompleteQuantityProgressTaskIDs = []
        let taskIDs = Set(tasks.map(\.id))
        recurrenceRules.removeAll {
            taskIDs.contains($0.templateTaskID) == false
        }
        let ruleByID = Dictionary(
            uniqueKeysWithValues: recurrenceRules.map { ($0.id, $0) }
        )
        recurrenceOccurrences.removeAll {
            ruleByID[$0.ruleID]?.templateTaskID != $0.templateTaskID ||
                taskIDs.contains($0.templateTaskID) == false ||
                taskIDs.contains($0.generatedTaskID) == false
        }
        quantityGoals.removeAll {
            taskIDs.contains($0.taskID) == false
        }
        let goalByID = Dictionary(
            uniqueKeysWithValues: quantityGoals.map { ($0.id, $0) }
        )
        for entry in quantityEntries {
            let goal = goalByID[entry.quantityGoalID]
            guard taskIDs.contains(entry.taskID) == false ||
                    goal?.taskID != entry.taskID else {
                continue
            }
            var participantIDs = Set<UUID>()
            if taskIDs.contains(entry.taskID) {
                participantIDs.insert(entry.taskID)
            }
            if let goal, taskIDs.contains(goal.taskID) {
                participantIDs.insert(goal.taskID)
            }
            incompleteQuantityProgressTaskIDs.formUnion(participantIDs)
        }
        quantityEntries.removeAll {
            taskIDs.contains($0.taskID) == false ||
                goalByID[$0.quantityGoalID]?.taskID != $0.taskID
        }
        recurrenceRules.sort { $0.id.uuidString < $1.id.uuidString }
        recurrenceOccurrences.sort { $0.id.uuidString < $1.id.uuidString }
        quantityGoals.sort { $0.id.uuidString < $1.id.uuidString }
        quantityEntries.sort {
            $0.recordedAt == $1.recordedAt
                ? $0.id.uuidString < $1.id.uuidString
                : $0.recordedAt < $1.recordedAt
        }
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
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
