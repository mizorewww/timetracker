import Foundation

struct TodayActivityHeatmapSnapshotService {
    static let daysPerWeek = 7

    func taskSnapshots(
        selectedTaskIDs: [UUID],
        tasks: [TaskNode],
        additionalContributingTaskIDsBySelectedTaskID: [UUID: Set<UUID>] = [:],
        segments: [TimeSegment],
        checklistItems: [ChecklistItem],
        quantityGoals: [TaskQuantityGoal],
        quantityEntries: [TaskQuantityEntry],
        period: ActivityHeatmapPeriod,
        now: Date,
        calendar: Calendar = .current
    ) async -> [TaskActivityHeatmapSnapshot] {
        let indexes = TaskTreeService().indexes(tasks: tasks)
        return await taskSnapshots(
            selectedTaskIDs: selectedTaskIDs,
            taskByID: indexes.taskByID,
            childrenByParentID: indexes.childrenByParentID,
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
    }

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
        let dateRange = dateRange(
            period: period,
            now: now,
            calendar: calendar
        )
        let indexes = await activityIndexes(
            taskByID: taskByID,
            segments: segments,
            checklistItems: checklistItems,
            quantityGoals: quantityGoals,
            quantityEntries: quantityEntries,
            interval: dateRange.interval,
            now: now,
            calendar: calendar
        )
        var seen = Set<UUID>()

        var snapshots: [TaskActivityHeatmapSnapshot] = []
        for selectedTaskID in selectedTaskIDs {
            // Heavy per-task projection (values + 53-week calendar work).
            // Yield between tasks so a first fast scroll stays responsive.
            await Task.yield()
            guard Task.isCancelled == false else { return snapshots }
            guard seen.insert(selectedTaskID).inserted,
                  let task = taskByID[selectedTaskID],
                  task.deletedAt == nil
            else {
                continue
            }
            var contributingRootTaskIDs =
                additionalContributingTaskIDsBySelectedTaskID[
                    selectedTaskID
                ] ?? []
            contributingRootTaskIDs.insert(selectedTaskID)
            let contributingIDs = contributingTaskIDs(
                selectedTaskIDs: Array(contributingRootTaskIDs),
                taskByID: taskByID,
                childrenByParentID: childrenByParentID
            )
            let values = values(
                selectedTaskID: selectedTaskID,
                contributingTaskIDs: contributingIDs,
                indexes: indexes,
                calendar: calendar
            )
            let maximumDailyValue = values.valuesByDay.values.max() ?? 0
            let weeks = weeks(
                valuesByDay: values.valuesByDay,
                referencesByDay: values.referencesByDay,
                defaultReferenceValue: maximumDailyValue,
                weekCount: period.weekCount,
                dateRange: dateRange,
                calendar: calendar
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
        tasks: [TaskNode]
    ) -> Set<UUID> {
        let indexes = TaskTreeService().indexes(tasks: tasks)
        return contributingTaskIDs(
            selectedTaskIDs: selectedTaskIDs,
            taskByID: indexes.taskByID,
            childrenByParentID: indexes.childrenByParentID
        )
    }

    func contributingTaskIDs(
        selectedTaskIDs: [UUID],
        taskByID: [UUID: TaskNode],
        childrenByParentID: [UUID?: [TaskNode]]
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
                contentsOf: (childrenByParentID[taskID] ?? []).lazy.map(\.id)
            )
        }
        return result
    }
}
