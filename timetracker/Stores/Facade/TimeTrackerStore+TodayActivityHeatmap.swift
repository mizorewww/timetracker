import Foundation

extension TimeTrackerStore {
    func todayActivityHeatmapSnapshot(
        now: Date,
        calendar: Calendar = .current
    ) -> ActivityHeatmapSnapshot {
        TodayActivityHeatmapSnapshotService().snapshot(
            selectedTaskIDs: preferences.todayHeatmapTaskIDs,
            taskByID: taskByID,
            childrenByParentID: childrenByParentID,
            checklistItems: checklistItems,
            now: now,
            calendar: calendar
        )
    }
}
