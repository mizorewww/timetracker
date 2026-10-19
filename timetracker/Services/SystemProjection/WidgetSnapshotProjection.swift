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
        var remainingTextBytes = SystemSurfaceLimits.maximumSnapshotTextBytes
        var activeTimers: [WidgetTimerSnapshot] = []
        for segment in activeSegments.prefix(SystemSurfaceLimits.maximumActiveTimers) {
            let task = taskByID[segment.taskID]
            let timer = WidgetTimerSnapshot(
                id: segment.id,
                taskID: segment.taskID,
                title: SystemSurfaceLimits.boundedTitle(
                    task?.title ?? AppStrings.localized("task.unavailable")
                ),
                path: SystemSurfaceLimits.boundedPath(
                    taskParentPathByID[segment.taskID] ?? ""
                ),
                startedAt: SystemSurfaceLimits.boundedTimerStart(
                    segment.startedAt,
                    generatedAt: generatedAt
                ),
                colorHex: SystemSurfaceLimits.boundedStyleValue(task?.colorHex),
                iconName: SystemSurfaceLimits.boundedStyleValue(task?.iconName)
            )
            guard timer.textByteCount <= remainingTextBytes else { break }
            activeTimers.append(timer)
            remainingTextBytes -= timer.textByteCount
        }

        var recentTaskSnapshots: [WidgetRecentTaskSnapshot] = []
        for task in recentTasks.prefix(SystemSurfaceLimits.maximumWidgetRecentTasks) {
            let recentTask = WidgetRecentTaskSnapshot(
                taskID: task.id,
                title: SystemSurfaceLimits.boundedTitle(task.title),
                path: SystemSurfaceLimits.boundedPath(
                    taskParentPathByID[task.id] ?? ""
                ),
                colorHex: SystemSurfaceLimits.boundedStyleValue(task.colorHex),
                iconName: SystemSurfaceLimits.boundedStyleValue(task.iconName)
            )
            guard recentTask.textByteCount <= remainingTextBytes else { break }
            recentTaskSnapshots.append(recentTask)
            remainingTextBytes -= recentTask.textByteCount
        }

        return WidgetSnapshot(
            generatedAt: generatedAt,
            todayGrossSeconds: SystemSurfaceLimits.boundedSummarySeconds(todayGrossSeconds),
            todayWallSeconds: SystemSurfaceLimits.boundedSummarySeconds(todayWallSeconds),
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
