import Foundation

extension TimeTrackerStore {
    func todayTaskActivityHeatmapSnapshots(
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
            now: now,
            calendar: calendar
        )
    }

}
