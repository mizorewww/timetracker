import Foundation

struct ActivityHeatmapDateRange {
    let interval: DateInterval
    let today: Date
}

struct ActivityHeatmapIndexes {
    let segmentIntervalsByTaskID: [UUID: [DateInterval]]
    let checklistTaskIDs: Set<UUID>
    let checklistValuesByTaskAndDay: [UUID: [Date: Int]]
    let quantityGoalByTaskID: [UUID: TaskQuantityGoal]
    let quantityValuesByTaskAndDay: [UUID: [Date: Int]]
}

struct ActivityHeatmapValues {
    let metric: ActivityHeatmapMetric
    let valuesByDay: [Date: Int]
    let referencesByDay: [Date: Int]
}

func normalizedHeatmapUnit(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}
