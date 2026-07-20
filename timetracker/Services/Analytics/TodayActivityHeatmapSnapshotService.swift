import Foundation

struct TodayActivityHeatmapSnapshotService {
    static let weekCount = 53
    static let daysPerWeek = 7

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
        let interval = DateInterval(start: intervalStart, end: intervalEnd)
        let contributingTaskIDs = contributingTaskIDs(
            selectedTaskIDs: selectedTaskIDs,
            taskByID: taskByID,
            childrenByParentID: childrenByParentID
        )
        let countsByDay = completionCountsByDay(
            contributingTaskIDs: contributingTaskIDs,
            checklistItems: checklistItems,
            interval: interval,
            now: now,
            calendar: calendar
        )

        var weeks: [ActivityHeatmapWeek] = []
        weeks.reserveCapacity(Self.weekCount)
        for weekIndex in 0..<Self.weekCount {
            guard let weekStart = calendar.date(
                byAdding: .weekOfYear,
                value: weekIndex,
                to: intervalStart
            ) else {
                continue
            }
            let days = (0..<Self.daysPerWeek).compactMap { dayIndex in
                calendar.date(
                    byAdding: .day,
                    value: dayIndex,
                    to: weekStart
                ).map { date in
                    let day = calendar.startOfDay(for: date)
                    let count = countsByDay[day, default: 0]
                    return ActivityHeatmapDay(
                        date: day,
                        completionCount: count,
                        intensity: ActivityHeatmapIntensity(
                            completionCount: count
                        ),
                        isFuture: day > today,
                        isToday: day == today
                    )
                }
            }
            weeks.append(
                ActivityHeatmapWeek(startDate: weekStart, days: days)
            )
        }

        return ActivityHeatmapSnapshot(
            interval: interval,
            today: today,
            weeks: weeks,
            totalCompletionCount: countsByDay.values.reduce(0, +),
            activeDayCount: countsByDay.values.lazy.filter { $0 > 0 }.count
        )
    }

    func contributingTaskIDs(
        selectedTaskIDs: [UUID],
        tasks: [TaskNode]
    ) -> Set<UUID> {
        let treeService = TaskTreeService()
        let indexes = treeService.indexes(tasks: tasks)
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
}
