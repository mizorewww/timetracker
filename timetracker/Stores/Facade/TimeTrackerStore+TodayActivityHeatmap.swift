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

    /// Compatibility for the original shared checklist heatmap while Today is
    /// migrated to task-specific snapshots.
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
