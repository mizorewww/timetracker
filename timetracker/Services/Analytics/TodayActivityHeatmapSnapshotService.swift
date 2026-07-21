import Foundation

struct TodayActivityHeatmapSnapshotService {
    static let weekCount = 53
    static let daysPerWeek = 7

    func taskSnapshots(
        selectedTaskIDs: [UUID],
        tasks: [TaskNode],
        segments: [TimeSegment],
        checklistItems: [ChecklistItem],
        quantityGoals: [TaskQuantityGoal],
        quantityEntries: [TaskQuantityEntry],
        now: Date,
        calendar: Calendar = .current
    ) -> [TaskActivityHeatmapSnapshot] {
        let indexes = TaskTreeService().indexes(tasks: tasks)
        return taskSnapshots(
            selectedTaskIDs: selectedTaskIDs,
            taskByID: indexes.taskByID,
            childrenByParentID: indexes.childrenByParentID,
            segments: segments,
            checklistItems: checklistItems,
            quantityGoals: quantityGoals,
            quantityEntries: quantityEntries,
            now: now,
            calendar: calendar
        )
    }

    func taskSnapshots(
        selectedTaskIDs: [UUID],
        taskByID: [UUID: TaskNode],
        childrenByParentID: [UUID?: [TaskNode]],
        segments: [TimeSegment],
        checklistItems: [ChecklistItem],
        quantityGoals: [TaskQuantityGoal],
        quantityEntries: [TaskQuantityEntry],
        now: Date,
        calendar: Calendar = .current
    ) -> [TaskActivityHeatmapSnapshot] {
        let dateRange = dateRange(now: now, calendar: calendar)
        let indexes = activityIndexes(
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

        return selectedTaskIDs.compactMap { selectedTaskID in
            guard seen.insert(selectedTaskID).inserted,
                  let task = taskByID[selectedTaskID],
                  task.deletedAt == nil else {
                return nil
            }
            let contributingIDs = contributingTaskIDs(
                selectedTaskIDs: [selectedTaskID],
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
                dateRange: dateRange,
                calendar: calendar
            )

            return TaskActivityHeatmapSnapshot(
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
        }
    }

    /// Compatibility for the original checklist-only Today presentation while
    /// it is migrated to `taskSnapshots`.
    func snapshot(
        selectedTaskIDs: [UUID],
        tasks: [TaskNode],
        checklistItems: [ChecklistItem],
        now: Date,
        calendar: Calendar = .current
    ) -> ActivityHeatmapSnapshot {
        let indexes = TaskTreeService().indexes(tasks: tasks)
        return snapshot(
            selectedTaskIDs: selectedTaskIDs,
            taskByID: indexes.taskByID,
            childrenByParentID: indexes.childrenByParentID,
            checklistItems: checklistItems,
            now: now,
            calendar: calendar
        )
    }

    func snapshot(
        selectedTaskIDs: [UUID],
        taskByID: [UUID: TaskNode],
        childrenByParentID: [UUID?: [TaskNode]],
        checklistItems: [ChecklistItem],
        now: Date,
        calendar: Calendar = .current
    ) -> ActivityHeatmapSnapshot {
        let dateRange = dateRange(now: now, calendar: calendar)
        let contributingTaskIDs = contributingTaskIDs(
            selectedTaskIDs: selectedTaskIDs,
            taskByID: taskByID,
            childrenByParentID: childrenByParentID
        )
        let countsByDay = completionCountsByDay(
            contributingTaskIDs: contributingTaskIDs,
            checklistItems: checklistItems,
            interval: dateRange.interval,
            now: now,
            calendar: calendar
        )
        let weeks = weeks(
            valuesByDay: countsByDay,
            referencesByDay: [:],
            defaultReferenceValue: 4,
            dateRange: dateRange,
            calendar: calendar
        )

        return ActivityHeatmapSnapshot(
            interval: dateRange.interval,
            today: dateRange.today,
            weeks: weeks,
            totalCompletionCount: countsByDay.values.reduce(0, +),
            activeDayCount: countsByDay.values.lazy.filter { $0 > 0 }.count
        )
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
                  result.insert(taskID).inserted else {
                continue
            }
            pending.append(
                contentsOf: (childrenByParentID[taskID] ?? []).lazy.map(\.id)
            )
        }
        return result
    }

    private func activityIndexes(
        taskByID: [UUID: TaskNode],
        segments: [TimeSegment],
        checklistItems: [ChecklistItem],
        quantityGoals: [TaskQuantityGoal],
        quantityEntries: [TaskQuantityEntry],
        interval: DateInterval,
        now: Date,
        calendar: Calendar
    ) -> ActivityHeatmapIndexes {
        let validTaskIDs = Set(taskByID.values.lazy.filter {
            $0.deletedAt == nil
        }.map(\.id))

        var segmentIntervalsByTaskID: [UUID: [DateInterval]] = [:]
        for segment in segments.visibleDeduplicatedByID() {
            guard validTaskIDs.contains(segment.taskID),
                  let clipped = TrackedTimePolicy.interval(
                    startedAt: segment.startedAt,
                    endedAt: segment.endedAt,
                    now: now,
                    clippedTo: interval
                  ) else {
                continue
            }
            segmentIntervalsByTaskID[segment.taskID, default: []].append(clipped)
        }

        var checklistTaskIDs = Set<UUID>()
        var checklistValuesByTaskAndDay: [UUID: [Date: Int]] = [:]
        for item in checklistItems.visibleDeduplicatedByID() {
            guard validTaskIDs.contains(item.taskID) else { continue }
            checklistTaskIDs.insert(item.taskID)
            guard item.isCompleted,
                  let completedAt = item.completedAt,
                  completedAt <= now else {
                continue
            }
            let day = calendar.startOfDay(for: completedAt)
            guard interval.contains(day) else { continue }
            checklistValuesByTaskAndDay[item.taskID, default: [:]][day, default: 0] += 1
        }

        var quantityGoalByTaskID: [UUID: TaskQuantityGoal] = [:]
        for goal in quantityGoals.visibleDeduplicatedByID() {
            guard validTaskIDs.contains(goal.taskID),
                  TaskQuantityPolicy.valueRange.contains(goal.targetAmount),
                  normalizedUnit(goal.unitLabel).isEmpty == false else {
                continue
            }
            if let current = quantityGoalByTaskID[goal.taskID],
               current.updatedAt >= goal.updatedAt {
                continue
            }
            quantityGoalByTaskID[goal.taskID] = goal
        }

        var quantityValuesByTaskAndDay: [UUID: [Date: Int]] = [:]
        for entry in quantityEntries.visibleDeduplicatedByID() {
            guard entry.amount > 0,
                  entry.recordedAt <= now,
                  let goal = quantityGoalByTaskID[entry.taskID],
                  entry.quantityGoalID == goal.id else {
                continue
            }
            let day = calendar.startOfDay(for: entry.recordedAt)
            guard interval.contains(day) else { continue }
            quantityValuesByTaskAndDay[entry.taskID, default: [:]][day, default: 0] += entry.amount
        }

        return ActivityHeatmapIndexes(
            segmentIntervalsByTaskID: segmentIntervalsByTaskID,
            checklistTaskIDs: checklistTaskIDs,
            checklistValuesByTaskAndDay: checklistValuesByTaskAndDay,
            quantityGoalByTaskID: quantityGoalByTaskID,
            quantityValuesByTaskAndDay: quantityValuesByTaskAndDay
        )
    }

    private func values(
        selectedTaskID: UUID,
        contributingTaskIDs: Set<UUID>,
        indexes: ActivityHeatmapIndexes,
        calendar: Calendar
    ) -> ActivityHeatmapValues {
        if let selectedGoal = indexes.quantityGoalByTaskID[selectedTaskID] {
            let unit = normalizedUnit(selectedGoal.unitLabel)
            let matchingGoals = contributingTaskIDs.compactMap { taskID in
                indexes.quantityGoalByTaskID[taskID]
            }.filter { normalizedUnit($0.unitLabel) == unit }
            var valuesByDay: [Date: Int] = [:]
            var contributingTaskIDsByDay: [Date: Set<UUID>] = [:]
            for goal in matchingGoals {
                for (day, amount) in indexes.quantityValuesByTaskAndDay[goal.taskID] ?? [:] {
                    valuesByDay[day, default: 0] += amount
                    contributingTaskIDsByDay[day, default: []].insert(goal.taskID)
                }
            }
            let referencesByDay = contributingTaskIDsByDay.mapValues { taskIDs in
                taskIDs.reduce(0) { total, taskID in
                    total + (indexes.quantityGoalByTaskID[taskID]?.targetAmount ?? 0)
                }
            }
            return ActivityHeatmapValues(
                metric: .quantity(unitLabel: selectedGoal.unitLabel),
                valuesByDay: valuesByDay,
                referencesByDay: referencesByDay
            )
        }

        if contributingTaskIDs.isDisjoint(with: indexes.checklistTaskIDs) == false {
            var valuesByDay: [Date: Int] = [:]
            for taskID in contributingTaskIDs {
                for (day, count) in indexes.checklistValuesByTaskAndDay[taskID] ?? [:] {
                    valuesByDay[day, default: 0] += count
                }
            }
            return ActivityHeatmapValues(
                metric: .checklistCompletions,
                valuesByDay: valuesByDay,
                referencesByDay: [:]
            )
        }

        let intervals = contributingTaskIDs.flatMap {
            indexes.segmentIntervalsByTaskID[$0] ?? []
        }
        return ActivityHeatmapValues(
            metric: .trackedDuration,
            valuesByDay: TimeAggregationService().secondsByDay(
                intervals: intervals,
                calendar: calendar
            ),
            referencesByDay: [:]
        )
    }

    private func weeks(
        valuesByDay: [Date: Int],
        referencesByDay: [Date: Int],
        defaultReferenceValue: Int,
        dateRange: ActivityHeatmapDateRange,
        calendar: Calendar
    ) -> [ActivityHeatmapWeek] {
        var result: [ActivityHeatmapWeek] = []
        result.reserveCapacity(Self.weekCount)
        for weekIndex in 0..<Self.weekCount {
            guard let weekStart = calendar.date(
                byAdding: .weekOfYear,
                value: weekIndex,
                to: dateRange.interval.start
            ) else {
                continue
            }
            let days = (0..<Self.daysPerWeek).compactMap { dayIndex in
                calendar.date(byAdding: .day, value: dayIndex, to: weekStart).map { date in
                    let day = calendar.startOfDay(for: date)
                    let isFuture = day > dateRange.today
                    let value = isFuture ? 0 : valuesByDay[day, default: 0]
                    let reference = referencesByDay[day] ?? defaultReferenceValue
                    return ActivityHeatmapDay(
                        date: day,
                        value: value,
                        referenceValue: reference,
                        intensity: isFuture
                            ? .none
                            : ActivityHeatmapIntensity(
                                value: value,
                                referenceValue: reference
                            ),
                        isFuture: isFuture,
                        isToday: day == dateRange.today
                    )
                }
            }
            result.append(ActivityHeatmapWeek(startDate: weekStart, days: days))
        }
        return result
    }

    private func dateRange(
        now: Date,
        calendar: Calendar
    ) -> ActivityHeatmapDateRange {
        let today = calendar.startOfDay(for: now)
        let currentWeekStart = calendar.dateInterval(
            of: .weekOfYear,
            for: now
        )?.start ?? today
        let intervalStart = calendar.date(
            byAdding: .weekOfYear,
            value: -(Self.weekCount - 1),
            to: currentWeekStart
        ) ?? currentWeekStart
        let intervalEnd = calendar.date(
            byAdding: .weekOfYear,
            value: 1,
            to: currentWeekStart
        ) ?? now
        return ActivityHeatmapDateRange(
            interval: DateInterval(start: intervalStart, end: intervalEnd),
            today: today
        )
    }

    private func completionCountsByDay(
        contributingTaskIDs: Set<UUID>,
        checklistItems: [ChecklistItem],
        interval: DateInterval,
        now: Date,
        calendar: Calendar
    ) -> [Date: Int] {
        guard contributingTaskIDs.isEmpty == false else { return [:] }
        var result: [Date: Int] = [:]
        for item in checklistItems.visibleDeduplicatedByID() {
            guard contributingTaskIDs.contains(item.taskID),
                  item.isCompleted,
                  let completedAt = item.completedAt,
                  completedAt <= now else {
                continue
            }
            let day = calendar.startOfDay(for: completedAt)
            guard interval.contains(day) else { continue }
            result[day, default: 0] += 1
        }
        return result
    }

    private func normalizedUnit(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private struct ActivityHeatmapDateRange {
    let interval: DateInterval
    let today: Date
}

private struct ActivityHeatmapIndexes {
    let segmentIntervalsByTaskID: [UUID: [DateInterval]]
    let checklistTaskIDs: Set<UUID>
    let checklistValuesByTaskAndDay: [UUID: [Date: Int]]
    let quantityGoalByTaskID: [UUID: TaskQuantityGoal]
    let quantityValuesByTaskAndDay: [UUID: [Date: Int]]
}

private struct ActivityHeatmapValues {
    let metric: ActivityHeatmapMetric
    let valuesByDay: [Date: Int]
    let referencesByDay: [Date: Int]
}
