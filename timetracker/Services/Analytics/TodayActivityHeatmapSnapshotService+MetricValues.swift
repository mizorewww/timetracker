import Foundation

extension TodayActivityHeatmapSnapshotService {
    func values(
        selectedTaskID: UUID,
        contributingTaskIDs: Set<UUID>,
        indexes: ActivityHeatmapIndexes,
        calendar: Calendar
    ) -> ActivityHeatmapValues {
        if let selectedGoal = indexes.quantityGoalByTaskID[selectedTaskID] {
            let unit = normalizedHeatmapUnit(selectedGoal.unitLabel)
            let matchingGoals = contributingTaskIDs.compactMap { taskID in
                indexes.quantityGoalByTaskID[taskID]
            }.filter { normalizedHeatmapUnit($0.unitLabel) == unit }
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
}
