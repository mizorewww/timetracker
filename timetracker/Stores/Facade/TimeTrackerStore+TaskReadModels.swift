import Foundation

extension TimeTrackerStore {
    var recentTasks: [TaskNode] {
        tasks
            .filter(isTaskAvailableForTracking)
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .prefix(4)
            .map { $0 }
    }

    func frequentRecentTasks(excluding excludedIDs: Set<UUID> = [], limit: Int = 3) -> [TaskNode] {
        let availableTasks = tasks.filter(isTaskAvailableForTracking)
        let activityByTaskID = taskUsageActivityByTaskID(
            for: availableTasks
        )
        let rankingService = TaskUsageRankingService()
        return rankingService.frequentRecentTasks(
            availableTasks: availableTasks,
            rankedTasks: rankingService.rankedTasks(
                availableTasks: availableTasks,
                activityByTaskID: activityByTaskID
            ),
            activityByTaskID: activityByTaskID,
            excluding: excludedIDs,
            limit: limit
        )
    }

    var archivedTasks: [TaskNode] {
        // SwiftData can merge sibling-context changes into existing @Model
        // instances without emitting an Observation change for each field.
        // The value-semantic task revision guarantees archive projections
        // invalidate even when the visible tree itself does not change.
        _ = taskReadModelRevision
        return tasks
            .filter { $0.deletedAt == nil && $0.isArchivedForLifecycle }
            .sorted { lhs, rhs in
                let lhsArchivedAt = lhs.archivedAt ?? .distantPast
                let rhsArchivedAt = rhs.archivedAt ?? .distantPast
                if lhsArchivedAt != rhsArchivedAt {
                    return lhsArchivedAt > rhsArchivedAt
                }
                if lhs.title.localizedStandardCompare(rhs.title) != .orderedSame {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    func hasArchivedAncestor(for task: TaskNode) -> Bool {
        taskTrackingAvailabilityService.hasArchivedAncestor(
            of: task,
            taskByID: taskByID,
            taskIDsToDisplayAsRoots: taskTreeIndexes.taskIDsToDisplayAsRoots
        )
    }

    func task(for id: UUID) -> TaskNode? {
        taskByID[id]
    }

    func rootTasks() -> [TaskNode] {
        taskTreeReadIndex.rootTaskIDs.compactMap { taskByID[$0] }
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
              let parent = taskByID[parentID]
        {
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
        (taskTreeReadIndex.visibleChildIDsByParentID[task.id] ?? []).compactMap { taskByID[$0] }
    }

    var visibleTaskCount: Int {
        taskTreeReadIndex.visibleTaskCount
    }

    func visibleChildCount(for taskID: UUID) -> Int {
        taskTreeReadIndex.visibleChildCount(for: taskID)
    }

    func validParentTasks(for taskID: UUID?) -> [TaskNode] {
        taskTreeService.validParentTasks(for: taskID, tasks: tasks)
    }

    func parentChangeBlocker(for task: TaskNode) -> TaskParentChangeBlocker? {
        taskTrackingAvailabilityService.parentChangeBlocker(for: task)
    }

    func preferredTaskIDForSelection() -> UUID? {
        activeSegments.first(where: { taskByID[$0.taskID] != nil })?.taskID ??
            tasks.first(where: isTaskAvailableForTracking)?.id
    }

    func hasActiveTimer(inTaskSubtree taskID: UUID) -> Bool {
        let subtreeIDs = taskAndDescendantIDs(for: taskID)
        if activeSegments.contains(where: { subtreeIDs.contains($0.taskID) }) {
            return true
        }
        return pomodoroRuns.contains { run in
            subtreeIDs.contains(run.taskID) &&
                run.deletedAt == nil &&
                run.endedAt == nil &&
                run.state != .completed &&
                run.state != .cancelled
        }
    }

    func taskTreeRows(expandedTaskIDs: Set<UUID>) -> [TaskTreeRowModel] {
        TaskTreeFlattener.rowProjection(
            rootTaskIDs: taskTreeReadIndex.rootTaskIDs,
            childTaskIDsByParentID: taskTreeReadIndex.visibleChildIDsByParentID,
            expandedTaskIDs: expandedTaskIDs
        ).rows
    }

    func taskTreeSections(expandedTaskIDs: Set<UUID>) -> [TaskTreeVisibleSectionModel] {
        let readIndex = taskTreeReadIndex
        let revision = taskTreeReadIndexRevision
        return taskTreeProjectionCache.projection(
            readIndex: readIndex,
            revision: revision,
            expandedTaskIDs: expandedTaskIDs
        ).sections
    }

    func taskSearchResults(matching query: String) -> [TaskNode] {
        let readIndex = taskTreeReadIndex
        let revision = taskTreeReadIndexRevision
        return taskTreeProjectionCache.searchProjection(
            readIndex: readIndex,
            revision: revision,
            query: query
        ).taskIDs.compactMap { taskByID[$0] }
    }

    /// Tasks-page row supplements (recurrence role + quantity progress).
    /// Built once per task-read-model revision: every input (recurrence
    /// rules/occurrences, quantity goals/entries, visibility) changes only
    /// through the task domain refresh, which bumps `taskReadModelRevision`.
    /// Rebuilds cost a full pass over all visible tasks, so repeated body
    /// evaluations of `TasksView` reuse the cached projection.
    func taskManagementRowSupplementProjection()
        -> TaskManagementRowSupplementProjection
    {
        if let cached = taskManagementRowSupplementProjectionCache,
           cached.revision == taskReadModelRevision
        {
            return cached.projection
        }
        let projection = TaskManagementRowSupplementProjection(store: self)
        taskManagementRowSupplementProjectionCache = (
            revision: taskReadModelRevision,
            projection: projection
        )
        return projection
    }

    func path(for task: TaskNode) -> String {
        taskPathByID[task.id] ?? task.title
    }

    func taskPath(for task: TaskNode) -> String {
        taskPathByID[task.id] ?? task.title
    }

    func parentPath(for task: TaskNode) -> String? {
        guard let path = taskParentPathByID[task.id], !path.isEmpty else { return nil }
        return path
    }

    func taskIdentityPresentation(for task: TaskNode) -> TaskIdentityPresentation {
        // The identity index is intentionally Observation-ignored. Track its
        // value-semantic revision so any row consuming a cached presentation
        // refreshes after sibling-context task edits are merged.
        _ = taskReadModelRevision
        return taskTreeIndexes.taskIdentityPresentation(for: task.id) ?? TaskIdentityPresentation(
            id: task.id,
            title: task.title,
            parentPath: nil,
            fullPath: task.title,
            visual: TaskVisualPresentation(
                iconName: task.iconName,
                colorHex: task.colorHex
            ),
            breadcrumb: .root(title: task.title)
        )
    }

    func rebuildTaskIndexes() {
        let indexes = taskTreeService.indexes(tasks: tasks)
        taskTreeIndexes = indexes
        taskByID = indexes.taskByID
        childrenByParentID = indexes.childrenByParentID
        taskPathByID = indexes.taskPathByID
        taskParentPathByID = indexes.taskParentPathByID
        let eligibility = taskTrackingAvailabilityService.eligibility(tasks: tasks)
        visibleTaskIDs = eligibility.visibleTaskIDs
        parentEligibleTaskIDs = eligibility.trackableTaskIDs
        trackableTaskIDs = taskTrackingAvailabilityService.directWorkTaskIDs(
            tasks: tasks,
            recurrenceRules: taskRecurrenceRules,
            recurrenceOccurrences: taskRecurrenceOccurrences
        ).subtracting(taskIDsWithIncompleteRecurrence)
        todayHeatmapRecurrenceProjection = TodayHeatmapRecurrenceProjection(
            taskByID: taskByID,
            recurrenceRules: taskRecurrenceRules,
            recurrenceOccurrences: taskRecurrenceOccurrences,
            incompleteTemplateTaskIDs:
            incompleteRecurrenceTemplateTaskIDs,
            incompleteGeneratedTaskIDs:
            incompleteRecurrenceGeneratedTaskIDs
        )
        rebuildTaskTreeReadIndex()
        rebuildForecastEligibilityIndex()
        taskReadModelRevision &+= 1
    }

    func rebuildTaskCategoryIndexes() {
        taskCategoryByID = taskCategories.visibleDeduplicatedByID().latestByID()
        let logicalWinners = taskCategoryAssignments
            .deduplicatedByID()
            .logicalWinnersByTaskID()
        taskCategoryAssignmentByRootTaskID = logicalWinners.filter {
            $0.value.deletedAt == nil
        }
        let categoryIDs: [UUID: UUID] = logicalWinners.compactMapValues { assignment -> UUID? in
            guard assignment.deletedAt == nil else { return nil }
            return assignment.categoryID
        }
        taskCategoryIDByRootTaskID = categoryIDs
        rebuildTaskTreeReadIndex()
        rebuildForecastEligibilityIndex()
    }

    func taskAndDescendantIDs(for taskID: UUID, visited: Set<UUID> = []) -> Set<UUID> {
        taskTreeService.taskAndDescendantIDs(for: taskID, childrenByParentID: childrenByParentID, visited: visited)
    }

    func forecastEligibleTaskIDs() -> Set<UUID> {
        forecastEligibleTaskIDCache
    }

    private func rebuildForecastEligibilityIndex() {
        forecastEligibleTaskIDCache = rootTasks().reduce(into: Set<UUID>()) { result, root in
            let includesInForecast = taskCategory(for: taskCategoryIDByRootTaskID[root.id])?.includesInForecast ?? true
            guard includesInForecast else { return }
            result.formUnion(taskAndDescendantIDs(for: root.id).intersection(trackableTaskIDs))
        }
    }

    private func rebuildTaskTreeReadIndex() {
        let nextIndex = taskTreeService.readIndex(
            indexes: taskTreeIndexes,
            visibleTaskIDs: visibleTaskIDs,
            categories: taskCategories,
            categoryIDByRootTaskID: taskCategoryIDByRootTaskID
        )
        guard nextIndex != taskTreeReadIndex else { return }
        taskTreeReadIndex = nextIndex
        taskTreeReadIndexRevision &+= 1
    }
}
