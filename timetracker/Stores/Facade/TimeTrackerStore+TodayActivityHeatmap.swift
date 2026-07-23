import Foundation

extension TimeTrackerStore {
    func todayTaskActivityHeatmapSnapshots(
        period: ActivityHeatmapPeriod,
        now: Date,
        calendar: Calendar = .current
    ) -> [TaskActivityHeatmapSnapshot] {
        TodayActivityHeatmapSnapshotService().taskSnapshots(
            selectedTaskIDs: preferences.todayHeatmapTaskIDs,
            taskByID: taskByID,
            childrenByParentID: childrenByParentID,
            segments: allSegments,
            checklistItems: checklistItems,
            quantityGoals: taskQuantityGoals,
            quantityEntries: taskQuantityEntries,
            period: period,
            now: now,
            calendar: calendar
        )
    }

}
