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
        var remainingTextBytes = WatchTransportLimits.maximumSnapshotTextBytes
        for timer in activeTimers {
            remainingTextBytes -= SystemSurfaceTextBounds.textByteCount(
                title: timer.title,
                path: timer.path,
                colorHex: timer.colorHex,
                iconName: timer.iconName
            )
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
            guard selected.count < WatchTransportLimits.maximumRecentTasks,
                  selected[task.id] == nil
            else {
                continue
            }
            let snapshot = WatchRecentTaskSnapshot(
                taskID: task.id,
                title: SystemSurfaceTextBounds.boundedUTF8Prefix(
                    task.title,
                    maximumUTF8Bytes: WatchTransportLimits.maximumProjectedTitleBytes
                ),
                path: SystemSurfaceTextBounds.boundedUTF8Prefix(
                    taskParentPathByID[task.id] ?? "",
                    maximumUTF8Bytes: WatchTransportLimits.maximumProjectedPathBytes
                ),
                colorHex: WatchTransportLimits.boundedProjectedStyleValue(task.colorHex),
                iconName: WatchTransportLimits.boundedProjectedStyleValue(task.iconName)
            )
            let textByteCount = SystemSurfaceTextBounds.textByteCount(
                title: snapshot.title,
                path: snapshot.path,
                colorHex: snapshot.colorHex,
                iconName: snapshot.iconName
            )
            guard textByteCount <= remainingTextBytes else { continue }
            selected[task.id] = snapshot
            remainingTextBytes -= textByteCount
        }

        var quickStartRank = 0
        for task in quickStartTasks
            where selected[task.id] != nil && selected[task.id]?.quickStartRank == nil
        {
            guard quickStartRank < WatchTransportLimits.maximumQuickStartTasks else { break }
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
