import Foundation

extension TodayActivityHeatmapSnapshotService {
    func activityIndexes(
        taskByID: [UUID: TaskNode],
        segments: [TimeSegment],
        checklistItems: [ChecklistItem],
        quantityGoals: [TaskQuantityGoal],
        quantityEntries: [TaskQuantityEntry],
        interval: DateInterval,
        now: Date,
        calendar: Calendar
    ) async -> ActivityHeatmapIndexes {
        let validTaskIDs = Set(taskByID.values.lazy.filter {
            $0.deletedAt == nil
        }.map(\.id))

        var segmentIntervalsByTaskID: [UUID: [DateInterval]] = [:]
        for (index, segment) in segments.visibleDeduplicatedByID().enumerated() {
            if index.isMultiple(of: 512) {
                await Task.yield()
                guard Task.isCancelled == false else {
                    return ActivityHeatmapIndexes.empty
                }
            }
            guard validTaskIDs.contains(segment.taskID),
                  let clipped = TrackedTimePolicy.interval(
                      startedAt: segment.startedAt,
                      endedAt: segment.endedAt,
                      now: now,
                      clippedTo: interval
                  )
            else {
                continue
            }
            segmentIntervalsByTaskID[segment.taskID, default: []].append(clipped)
        }

        var checklistTaskIDs = Set<UUID>()
        var checklistValuesByTaskAndDay: [UUID: [Date: Int]] = [:]
        for (index, item) in checklistItems.visibleDeduplicatedByID().enumerated() {
            if index.isMultiple(of: 512) {
                await Task.yield()
            }
            guard validTaskIDs.contains(item.taskID) else { continue }
            checklistTaskIDs.insert(item.taskID)
            guard item.isCompleted,
                  let completedAt = item.completedAt,
                  completedAt <= now
            else {
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
                  normalizedHeatmapUnit(goal.unitLabel).isEmpty == false
            else {
                continue
            }
            if let current = quantityGoalByTaskID[goal.taskID],
               current.updatedAt >= goal.updatedAt
            {
                continue
            }
            quantityGoalByTaskID[goal.taskID] = goal
        }

        var quantityValuesByTaskAndDay: [UUID: [Date: Int]] = [:]
        for entry in quantityEntries.visibleDeduplicatedByID() {
            guard entry.amount > 0,
                  entry.recordedAt <= now,
                  let goal = quantityGoalByTaskID[entry.taskID],
                  entry.quantityGoalID == goal.id
            else {
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
}
