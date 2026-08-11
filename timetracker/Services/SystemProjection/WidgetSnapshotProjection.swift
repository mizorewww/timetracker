import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

nonisolated enum WidgetSnapshotProjection {
    @MainActor
    static func reloadTimelines() {
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

/// Serializes Widget payload encoding and App Group persistence away from
/// MainActor. WidgetKit invalidation returns to MainActor only after the new
/// immutable snapshot is durable.
actor WidgetSnapshotProjectionWriter {
    typealias Persistence = @Sendable (WidgetSnapshot) throws -> Void
    typealias TimelineReloader = @MainActor @Sendable () -> Void

    private let store: SharedWidgetSnapshotStore?
    private let persistSnapshot: Persistence?
    private let reloadTimelines: TimelineReloader

    init() {
        store = SharedWidgetSnapshotStore()
        persistSnapshot = nil
        reloadTimelines = {
            WidgetSnapshotProjection.reloadTimelines()
        }
    }

    init(
        persist: @escaping Persistence,
        reload: @escaping TimelineReloader = {}
    ) {
        store = nil
        persistSnapshot = persist
        reloadTimelines = reload
    }

    func save(_ snapshot: WidgetSnapshot) async throws {
        if let persistSnapshot {
            try persistSnapshot(snapshot)
        } else {
            try store?.save(snapshot)
        }
        await reloadTimelines()
    }
}
