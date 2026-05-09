import Foundation

extension TimeTrackerStore {
    func syncWidgetSnapshotIfAvailable(now: Date = Date()) {
        let activeTaskIDs = Set(activeSegments.map(\.taskID))
        let snapshot = WidgetSnapshotCache.snapshot(
            activeSegments: activeSegments,
            taskByID: taskByID,
            taskParentPathByID: taskParentPathByID,
            recentTasks: frequentRecentTasks(excluding: activeTaskIDs, limit: 3),
            todayGrossSeconds: todayGrossSeconds(now: now),
            todayWallSeconds: todayWallSeconds(now: now),
            generatedAt: now
        )
        try? WidgetSnapshotCache().save(snapshot)
    }
}
