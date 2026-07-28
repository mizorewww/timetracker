import Foundation

extension TimeTrackerStore {
    func watchStateSnapshot(now: Date = Date()) -> WatchStateSnapshot {
        let availableTasks = tasks.filter(isTaskAvailableForTracking)
        let activityByTaskID = taskUsageActivityByTaskID(
            for: availableTasks
        )
        let rankingService = TaskUsageRankingService()
        let rankedTasks = rankingService.rankedTasks(
            availableTasks: availableTasks,
            activityByTaskID: activityByTaskID
        )
        let legacyOrderedTasks = rankingService.legacyWatchTaskOrder(
            availableTasks: availableTasks,
            rankedTasks: rankedTasks,
            activityByTaskID: activityByTaskID,
            quickStartTaskIDs: preferences.quickStartTaskIDs,
            taskPathByID: taskPathByID
        )
        let widgetSnapshot = WidgetSnapshotCache.snapshot(
            activeSegments: activeSegments,
            taskByID: taskByID,
            taskParentPathByID: taskParentPathByID,
            recentTasks: [],
            todayGrossSeconds: todayGrossSeconds(now: now),
            todayWallSeconds: todayWallSeconds(now: now),
            generatedAt: now
        )
        return WatchStateProjectionService().snapshot(
            widgetSnapshot: widgetSnapshot,
            rankedTasks: rankedTasks,
            legacyOrderedTasks: legacyOrderedTasks,
            taskParentPathByID: taskParentPathByID,
            quickStartTaskIDs: preferences.quickStartTaskIDs
        )
    }
}
