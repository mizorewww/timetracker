import Foundation

/// Builds the bounded Watch transport value from already loaded facts. The
/// wire array is in usage order; `quickStartRank` orders the Quick Start page.
/// Selection priority under the byte budget is active timers, then Quick Start
/// tasks, then the remaining tasks by usage.
nonisolated struct WatchStateProjectionService {
    func snapshot(
        widgetSnapshot: WidgetSnapshot,
        rankedTasks: [TaskNode],
        quickStartTasks: [TaskNode],
        taskParentPathByID: [UUID: String]
    ) -> WatchStateSnapshot {
        let activeTimers = widgetSnapshot.activeTimers
        var remainingTextBytes = SystemSurfaceLimits.maximumSnapshotTextBytes
        for timer in activeTimers {
            remainingTextBytes -= timer.textByteCount
        }

        let usageRankByTaskID = Dictionary(
            rankedTasks.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        let taskByID = Dictionary(
            rankedTasks.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let activeTaskIDs = Set(activeTimers.map(\.taskID))
        let candidates = rankedTasks.filter { activeTaskIDs.contains($0.id) }
            + quickStartTasks.compactMap { taskByID[$0.id] }
            + rankedTasks

        var selected: [UUID: WatchRecentTaskSnapshot] = [:]
        for task in candidates {
            guard selected.count < SystemSurfaceLimits.maximumWatchTasks,
                  selected[task.id] == nil
            else {
                continue
            }
            let snapshot = WatchRecentTaskSnapshot(
                taskID: task.id,
                title: SystemSurfaceLimits.boundedTitle(task.title),
                path: SystemSurfaceLimits.boundedPath(taskParentPathByID[task.id] ?? ""),
                colorHex: SystemSurfaceLimits.boundedStyleValue(task.colorHex),
                iconName: SystemSurfaceLimits.boundedStyleValue(task.iconName)
            )
            guard snapshot.textByteCount <= remainingTextBytes else { continue }
            selected[task.id] = snapshot
            remainingTextBytes -= snapshot.textByteCount
        }

        var quickStartRank = 0
        for task in quickStartTasks
            where selected[task.id] != nil && selected[task.id]?.quickStartRank == nil
        {
            guard quickStartRank < SystemSurfaceLimits.maximumQuickStartTasks else { break }
            selected[task.id]?.quickStartRank = quickStartRank
            quickStartRank += 1
        }

        return WatchStateSnapshot(
            generatedAt: widgetSnapshot.generatedAt,
            todayGrossSeconds: widgetSnapshot.todayGrossSeconds,
            todayWallSeconds: widgetSnapshot.todayWallSeconds,
            activeTimers: activeTimers,
            recentTasks: selected.values.sorted {
                (usageRankByTaskID[$0.taskID] ?? .max) <
                    (usageRankByTaskID[$1.taskID] ?? .max)
            }
        )
    }
}
