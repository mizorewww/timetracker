import Foundation

extension TimeTrackerStore {
    var recentTasks: [TaskNode] {
        tasks
            .filter { $0.status == .active && isTaskAvailableForTracking($0) }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .prefix(4)
            .map { $0 }
    }

    func frequentRecentTasks(excluding excludedIDs: Set<UUID> = [], limit: Int = 3) -> [TaskNode] {
        guard limit > 0 else { return [] }

        let availableTasks = tasks.filter {
            isTaskAvailableForTracking($0) &&
            !excludedIDs.contains($0.id)
        }
        let rankedTasks = availableTasks.compactMap { task -> (task: TaskNode, count: Int, lastStartedAt: Date)? in
            guard let activity = rollupDomainStore.activitySummary(for: task.id) else { return nil }
            return (task, activity.segmentCount, activity.lastStartedAt)
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

    func isTaskAvailableForTracking(_ task: TaskNode) -> Bool {
        trackableTaskIDs.contains(task.id)
    }

    func isTaskVisible(_ task: TaskNode) -> Bool {
        visibleTaskIDs.contains(task.id)
    }

    func completedWorkBlockers(for task: TaskNode) -> [TaskNode] {
        taskTrackingAvailabilityService
            .completedBlockingTaskIDs(for: task.id, tasks: tasks)
            .compactMap { taskByID[$0] }
    }

    func completedWorkBlocker(for task: TaskNode) -> TaskNode? {
        completedWorkBlockers(for: task).last
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
        taskTreeIndexes.taskIdentityPresentation(for: task.id) ?? TaskIdentityPresentation(
            id: task.id,
            title: task.title,
            parentPath: nil,
            fullPath: task.title,
            visual: TaskVisualPresentation(
                iconName: task.iconName,
                colorHex: task.colorHex
            )
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
        trackableTaskIDs = eligibility.trackableTaskIDs
        rebuildTaskTreeReadIndex()
        rebuildForecastEligibilityIndex()
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
