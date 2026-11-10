import Foundation

nonisolated struct TodayActivityHeatmapSnapshotService: Sendable {
    static let daysPerWeek = 7

    @MainActor
    func taskSnapshots(
        selectedTaskIDs: [UUID],
        taskByID: [UUID: TaskNode],
        childrenByParentID: [UUID?: [TaskNode]],
        additionalContributingTaskIDsBySelectedTaskID: [UUID: Set<UUID>] = [:],
        segments: [TimeSegment],
        checklistItems: [ChecklistItem],
        quantityGoals: [TaskQuantityGoal],
        quantityEntries: [TaskQuantityEntry],
        period: ActivityHeatmapPeriod,
        now: Date,
        calendar: Calendar = .current
    ) async -> [TaskActivityHeatmapSnapshot] {
        guard selectedTaskIDs.isEmpty == false else { return [] }
        let input = ActivityHeatmapSnapshotInput(
            selectedTaskIDs: selectedTaskIDs,
            taskByID: taskByID,
            childrenByParentID: childrenByParentID,
            additionalContributingTaskIDsBySelectedTaskID:
            additionalContributingTaskIDsBySelectedTaskID,
            segments: segments,
            checklistItems: checklistItems,
            quantityGoals: quantityGoals,
            quantityEntries: quantityEntries,
            period: period,
            now: now,
            calendar: calendar
        )
        return await Self.buildSnapshots(input)
    }

    @concurrent
    static func buildSnapshots(
        _ input: ActivityHeatmapSnapshotInput
    ) async -> [TaskActivityHeatmapSnapshot] {
        await TodayActivityHeatmapSnapshotService().taskSnapshots(input)
    }

    func taskSnapshots(
        _ input: ActivityHeatmapSnapshotInput
    ) async -> [TaskActivityHeatmapSnapshot] {
        let dateRange = dateRange(
            period: input.period,
            now: input.now,
            calendar: input.calendar
        )
        let indexes = await activityIndexes(
            taskByID: input.taskByID,
            segments: input.segments,
            checklistItems: input.checklistItems,
            quantityGoals: input.quantityGoals,
            quantityEntries: input.quantityEntries,
            interval: dateRange.interval,
            now: input.now,
            calendar: input.calendar
        )
        var seen = Set<UUID>()

        var snapshots: [TaskActivityHeatmapSnapshot] = []
        for selectedTaskID in input.selectedTaskIDs {
            await Task.yield()
            guard Task.isCancelled == false else { return snapshots }
            guard seen.insert(selectedTaskID).inserted,
                  let task = input.taskByID[selectedTaskID],
                  task.deletedAt == nil
            else {
                continue
            }
            var contributingRootTaskIDs =
                input.additionalContributingTaskIDsBySelectedTaskID[
                    selectedTaskID
                ] ?? []
            contributingRootTaskIDs.insert(selectedTaskID)
            let contributingIDs = contributingTaskIDs(
                selectedTaskIDs: Array(contributingRootTaskIDs),
                taskByID: input.taskByID,
                childIDsByParentID: input.childIDsByParentID
            )
            let values = values(
                selectedTaskID: selectedTaskID,
                contributingTaskIDs: contributingIDs,
                indexes: indexes,
                calendar: input.calendar
            )
            let maximumDailyValue = values.valuesByDay.values.max() ?? 0
            let weeks = weeks(
                valuesByDay: values.valuesByDay,
                referencesByDay: values.referencesByDay,
                defaultReferenceValue: maximumDailyValue,
                weekCount: input.period.weekCount,
                dateRange: dateRange,
                calendar: input.calendar
            )

            snapshots.append(
                TaskActivityHeatmapSnapshot(
                    taskID: selectedTaskID,
                    title: task.title,
                    iconName: ChecklistVisualSanitizer.sanitizedIcon(task.iconName),
                    colorHex: ChecklistVisualSanitizer.sanitizedColor(task.colorHex),
                    metric: values.metric,
                    interval: dateRange.interval,
                    today: dateRange.today,
                    weeks: weeks,
                    totalValue: values.valuesByDay.values.reduce(0, +),
                    activeDayCount: values.valuesByDay.values.lazy.filter { $0 > 0 }.count,
                    maximumDailyValue: maximumDailyValue
                )
            )
        }
        return snapshots
    }

    func contributingTaskIDs(
        selectedTaskIDs: [UUID],
        taskByID: [UUID: ActivityHeatmapTaskRecord],
        childIDsByParentID: [UUID?: [UUID]]
    ) -> Set<UUID> {
        var result = Set<UUID>()
        var pending = Array(Set(selectedTaskIDs.filter { taskID in
            guard let task = taskByID[taskID] else { return false }
            return task.deletedAt == nil
        }))
        while let taskID = pending.popLast() {
            guard let task = taskByID[taskID],
                  task.deletedAt == nil,
                  result.insert(taskID).inserted
            else {
                continue
            }
            pending.append(
                contentsOf: childIDsByParentID[taskID] ?? []
            )
        }
        return result
    }
}
