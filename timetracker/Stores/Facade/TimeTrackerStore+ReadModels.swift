import Foundation

extension TimeTrackerStore {
    var selectedTask: TaskNode? {
        guard let selectedTaskID else { return nil }
        return task(for: selectedTaskID)
    }

    var activePomodoroRun: PomodoroRun? {
        pomodoroRuns.first { run in
            run.deletedAt == nil &&
            run.endedAt == nil &&
            [.planned, .focusing, .shortBreak, .longBreak, .interrupted].contains(run.state)
        }
    }

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

    var syncStatus: SyncStatus {
        SyncStatus(
            mode: AppCloudSync.persistenceMode,
            containerIdentifier: AppCloudSync.containerIdentifier,
            deviceID: DeviceIdentity.current,
            lastError: AppCloudSync.lastError,
            accountStatus: cloudAccountStatus
        )
    }

    var timelineSegments: [TimeSegment] {
        sortedTodaySegments
    }

    var todayGrossSeconds: Int {
        todayGrossSeconds(now: Date())
    }

    var todayWallSeconds: Int {
        todayWallSeconds(now: Date())
    }

    func todayGrossSeconds(now: Date) -> Int {
        aggregationService.totalSeconds(segments: todaySegments, mode: .gross, now: now)
    }

    func todayWallSeconds(now: Date) -> Int {
        aggregationService.totalSeconds(segments: todaySegments, mode: .wallClock, now: now)
    }

    func daySeconds(for date: Date, mode: AggregationMode = .gross, now: Date = Date()) -> Int {
        guard let interval = Calendar.current.dateInterval(of: .day, for: date) else { return 0 }
        return ledgerSummaryService.secondsInInterval(
            taskIDs: Set(allSegments.map(\.taskID)),
            segments: allSegments,
            interval: interval,
            mode: mode,
            now: now
        )
    }

    func overlapSeconds(now: Date) -> Int {
        max(0, todayGrossSeconds(now: now) - todayWallSeconds(now: now))
    }

    var overlapSeconds: Int {
        max(0, todayGrossSeconds - todayWallSeconds)
    }

    var completedPomodoroCount: Int {
        let today = Calendar.current.dateInterval(of: .day, for: Date())
        return pomodoroRuns.filter { run in
            run.state == .completed &&
            run.deletedAt == nil &&
            today?.contains(run.endedAt ?? run.updatedAt) == true
        }.count
    }

    var averageFocusSeconds: Int {
        let focus = todaySegments.filter { $0.source == .pomodoro }
        guard !focus.isEmpty else { return 0 }
        return aggregationService.grossSeconds(focus) / focus.count
    }

    func task(for id: UUID) -> TaskNode? {
        taskByID[id]
    }

    func activeSegment(for taskID: UUID) -> TimeSegment? {
        activeSegments.first { $0.taskID == taskID }
    }

    func pausedSession(for taskID: UUID) -> TimeSession? {
        pausedSessions.first { $0.taskID == taskID }
    }

    func activePomodoroRun(for taskID: UUID) -> PomodoroRun? {
        pomodoroRuns.first { run in
            run.taskID == taskID &&
            run.deletedAt == nil &&
            run.endedAt == nil &&
            [.planned, .focusing, .shortBreak, .longBreak, .interrupted].contains(run.state)
        }
    }

    func taskTitle(for run: PomodoroRun) -> String {
        task(for: run.taskID)?.title ?? AppStrings.localized("task.deleted")
    }

    func pomodoroRemainingSeconds(for run: PomodoroRun, now: Date = Date()) -> Int {
        guard [.focusing, .interrupted].contains(run.state) else {
            return run.focusSecondsPlanned
        }
        return max(0, run.focusSecondsPlanned - pomodoroElapsedFocusSeconds(for: run, now: now))
    }

    func pomodoroProgress(for run: PomodoroRun, now: Date = Date()) -> Double {
        guard run.focusSecondsPlanned > 0 else { return 0 }
        let remaining = pomodoroRemainingSeconds(for: run, now: now)
        return min(1, max(0, 1 - Double(remaining) / Double(run.focusSecondsPlanned)))
    }

    func pomodoroStateLabel(for run: PomodoroRun) -> String {
        switch run.state {
        case .planned:
            return AppStrings.localized("pomodoro.state.ready")
        case .focusing:
            return AppStrings.localized("pomodoro.state.focus")
        case .shortBreak:
            return AppStrings.localized("pomodoro.state.shortBreak")
        case .longBreak:
            return AppStrings.localized("pomodoro.state.longBreak")
        case .completed:
            return AppStrings.localized("pomodoro.state.completed")
        case .cancelled:
            return AppStrings.localized("pomodoro.state.cancelled")
        case .interrupted:
            return AppStrings.localized("pomodoro.state.interrupted")
        }
    }

    func pomodoroElapsedFocusSeconds(for run: PomodoroRun, now: Date = Date()) -> Int {
        guard let sessionID = run.sessionID else { return 0 }
        let segments = allSegments.filter { segment in
            segment.sessionID == sessionID &&
            segment.source == .pomodoro &&
            segment.deletedAt == nil
        }
        return aggregationService.grossSeconds(segments, now: now)
    }

    func path(for task: TaskNode) -> String {
        taskPathByID[task.id] ?? task.title
    }

    func displayTitle(for segment: TimeSegment) -> String {
        task(for: segment.taskID)?.title ?? AppStrings.localized("task.deleted")
    }

    func displayPath(for segment: TimeSegment) -> String {
        guard taskByID[segment.taskID] != nil else { return AppStrings.localized("task.deleted.path") }
        return taskParentPathByID[segment.taskID] ?? ""
    }

    func note(for segment: TimeSegment) -> String {
        sessions.first { $0.id == segment.sessionID }?.note ?? ""
    }

    func secondsForTaskTotal(_ task: TaskNode, mode: AggregationMode = .gross, now: Date = Date()) -> Int {
        ledgerSummaryService.totalSeconds(taskIDs: [task.id], segments: allSegments, mode: mode, now: now)
    }

    func secondsForTaskTotalRollup(_ task: TaskNode, mode: AggregationMode = .gross, now: Date = Date()) -> Int {
        let ids = taskAndDescendantIDs(for: task.id)
        return ledgerSummaryService.totalSeconds(taskIDs: ids, segments: allSegments, mode: mode, now: now)
    }

    func secondsForTaskToday(_ task: TaskNode, mode: AggregationMode = .gross) -> Int {
        let now = Date()
        guard let interval = Calendar.current.dateInterval(of: .day, for: now) else { return 0 }
        return ledgerSummaryService.secondsInInterval(taskIDs: [task.id], segments: allSegments, interval: interval, mode: mode, now: now)
    }

    func secondsForTaskTodayRollup(_ task: TaskNode, mode: AggregationMode = .gross, now: Date = Date()) -> Int {
        guard let interval = Calendar.current.dateInterval(of: .day, for: now) else { return 0 }
        let ids = taskAndDescendantIDs(for: task.id)
        return ledgerSummaryService.secondsInInterval(taskIDs: ids, segments: allSegments, interval: interval, mode: mode, now: now)
    }

    func secondsForTaskThisWeek(_ task: TaskNode, mode: AggregationMode = .gross, now: Date = Date()) -> Int {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return ledgerSummaryService.secondsInInterval(taskIDs: [task.id], segments: allSegments, interval: interval, mode: mode, now: now)
    }

    func secondsForTaskThisWeekRollup(_ task: TaskNode, mode: AggregationMode = .gross, now: Date = Date()) -> Int {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        let ids = taskAndDescendantIDs(for: task.id)
        return ledgerSummaryService.secondsInInterval(taskIDs: ids, segments: allSegments, interval: interval, mode: mode, now: now)
    }

    func recentSegments(for task: TaskNode, limit: Int = 6) -> [TimeSegment] {
        allSegments
            .filter { $0.taskID == task.id && $0.deletedAt == nil }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(limit)
            .map { $0 }
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
        taskCategory(for: rootTask(for: task).categoryID)
    }

    func children(of task: TaskNode) -> [TaskNode] {
        childrenByParentID[task.id] ?? []
    }

    func ancestorTaskIDs(for taskID: UUID) -> [UUID] {
        var result: [UUID] = []
        var cursor = taskByID[taskID]
        var visited: Set<UUID> = []
        while let parentID = cursor?.parentID, !visited.contains(parentID) {
            result.append(parentID)
            visited.insert(parentID)
            cursor = taskByID[parentID]
        }
        return result
    }

    func affectedAncestorIDs(for taskID: UUID?, parentID: UUID? = nil) -> Set<UUID> {
        var ids: Set<UUID> = []
        if let taskID {
            ids.formUnion(ancestorTaskIDs(for: taskID))
        }
        if let parentID {
            ids.insert(parentID)
            ids.formUnion(ancestorTaskIDs(for: parentID))
        }
        return ids
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
        taskTreeService.categorySections(rootTasks: rootTasks(), categories: taskCategories).map { section in
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

    func checklistItems(for taskID: UUID) -> [ChecklistItem] {
        checklistByTaskID[taskID] ?? []
    }

    func checklistProgress(for taskID: UUID) -> ChecklistProgress {
        rollupDomainStore.checklistProgress(for: taskID, checklistItems: checklistItems)
    }

    func rollup(for taskID: UUID) -> TaskRollup? {
        rollupDomainStore.rollup(for: taskID)
    }

    func forecastDisplayItems(limit: Int? = nil) -> [ForecastDisplayItem] {
        forecastDisplayService.displayItems(tasks: tasks, rollups: rollupDomainStore.taskRollups, limit: limit)
    }

    func forecastDisplayItem(for taskID: UUID) -> ForecastDisplayItem? {
        forecastDisplayService.displayItem(for: taskID, tasks: tasks, rollups: rollupDomainStore.taskRollups)
    }

    func rebuildTaskIndexes() {
        let indexes = taskTreeService.indexes(tasks: tasks)
        taskByID = indexes.taskByID
        childrenByParentID = indexes.childrenByParentID
        taskPathByID = indexes.taskPathByID
        taskParentPathByID = indexes.taskParentPathByID
    }

    func rebuildChecklistIndexes() {
        checklistByTaskID = Dictionary(grouping: checklistItems.filter { $0.deletedAt == nil }, by: \.taskID)
            .mapValues { items in
                items.sorted { lhs, rhs in
                    if lhs.sortOrder == rhs.sortOrder {
                        return lhs.createdAt < rhs.createdAt
                    }
                    return lhs.sortOrder < rhs.sortOrder
                }
            }
    }

    func rebuildTaskCategoryIndexes() {
        taskCategoryByID = Dictionary(uniqueKeysWithValues: taskCategories.filter { $0.deletedAt == nil }.map { ($0.id, $0) })
    }

    private func taskAndDescendantIDs(for taskID: UUID, visited: Set<UUID> = []) -> Set<UUID> {
        taskTreeService.taskAndDescendantIDs(for: taskID, childrenByParentID: childrenByParentID, visited: visited)
    }

    func forecastEligibleTaskIDs() -> Set<UUID> {
        rootTasks().reduce(into: Set<UUID>()) { result, root in
            let includesInForecast = taskCategory(for: root.categoryID)?.includesInForecast ?? true
            guard includesInForecast else { return }
            result.formUnion(taskAndDescendantIDs(for: root.id))
        }
    }
}
