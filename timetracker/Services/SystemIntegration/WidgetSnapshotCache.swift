import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

struct WidgetSnapshotCache {
    var store: SharedWidgetSnapshotStore

    init(store: SharedWidgetSnapshotStore = SharedWidgetSnapshotStore()) {
        self.store = store
    }

    func save(_ snapshot: WidgetSnapshot) throws {
        try store.save(snapshot)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: SharedWidgetSnapshotStore.widgetKind)
        #endif
    }

    nonisolated static func snapshot(
        activeSegments: [TimeSegment],
        taskByID: [UUID: TaskNode],
        taskParentPathByID: [UUID: String],
        recentTasks: [TaskNode] = [],
        todayGrossSeconds: Int,
        todayWallSeconds: Int,
        generatedAt: Date
    ) -> WidgetSnapshot {
        var remainingTextBytes = WidgetSnapshotLimits.maximumSnapshotTextBytes
        var activeTimers: [WidgetTimerSnapshot] = []
        for segment in activeSegments.prefix(WidgetSnapshotLimits.maximumActiveTimers) {
            let task = taskByID[segment.taskID]
            let timer = WidgetTimerSnapshot(
                id: segment.id,
                taskID: segment.taskID,
                title: WidgetSnapshotLimits.boundedUTF8Prefix(
                    task?.title ?? AppStrings.localized("task.unavailable"),
                    maximumUTF8Bytes: WidgetSnapshotLimits.maximumProjectedTitleBytes
                ),
                path: WidgetSnapshotLimits.boundedUTF8Prefix(
                    taskParentPathByID[segment.taskID] ?? "",
                    maximumUTF8Bytes: WidgetSnapshotLimits.maximumProjectedPathBytes
                ),
                startedAt: WidgetSnapshotLimits.boundedTimerStart(
                    segment.startedAt,
                    generatedAt: generatedAt
                ),
                colorHex: WidgetSnapshotLimits.boundedProjectedStyleValue(task?.colorHex),
                iconName: WidgetSnapshotLimits.boundedProjectedStyleValue(task?.iconName)
            )
            let textByteCount = WidgetSnapshotLimits.textByteCount(
                title: timer.title,
                path: timer.path,
                colorHex: timer.colorHex,
                iconName: timer.iconName
            )
            guard textByteCount <= remainingTextBytes else { break }
            activeTimers.append(timer)
            remainingTextBytes -= textByteCount
        }

        var recentTaskSnapshots: [WidgetRecentTaskSnapshot] = []
        for task in recentTasks.prefix(min(3, WidgetSnapshotLimits.maximumRecentTasks)) {
            let recentTask = WidgetRecentTaskSnapshot(
                taskID: task.id,
                title: WidgetSnapshotLimits.boundedUTF8Prefix(
                    task.title,
                    maximumUTF8Bytes: WidgetSnapshotLimits.maximumProjectedTitleBytes
                ),
                path: WidgetSnapshotLimits.boundedUTF8Prefix(
                    taskParentPathByID[task.id] ?? "",
                    maximumUTF8Bytes: WidgetSnapshotLimits.maximumProjectedPathBytes
                ),
                colorHex: WidgetSnapshotLimits.boundedProjectedStyleValue(task.colorHex),
                iconName: WidgetSnapshotLimits.boundedProjectedStyleValue(task.iconName)
            )
            let textByteCount = WidgetSnapshotLimits.textByteCount(
                title: recentTask.title,
                path: recentTask.path,
                colorHex: recentTask.colorHex,
                iconName: recentTask.iconName
            )
            guard textByteCount <= remainingTextBytes else { break }
            recentTaskSnapshots.append(recentTask)
            remainingTextBytes -= textByteCount
        }

        return WidgetSnapshot(
            generatedAt: generatedAt,
            todayGrossSeconds: min(max(0, todayGrossSeconds), WidgetSnapshotLimits.maximumSummarySeconds),
            todayWallSeconds: min(max(0, todayWallSeconds), WidgetSnapshotLimits.maximumSummarySeconds),
            activeTimers: activeTimers,
            recentTasks: recentTaskSnapshots
        )
    }
}
