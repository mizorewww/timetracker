import Foundation

struct WidgetSnapshotCache {
    var store: SharedWidgetSnapshotStore

    init(store: SharedWidgetSnapshotStore = SharedWidgetSnapshotStore()) {
        self.store = store
    }

    func save(_ snapshot: WidgetSnapshot) throws {
        try store.save(snapshot)
    }

    static func snapshot(
        activeSegments: [TimeSegment],
        taskByID: [UUID: TaskNode],
        taskParentPathByID: [UUID: String],
        recentTasks: [TaskNode] = [],
        todayGrossSeconds: Int,
        todayWallSeconds: Int,
        generatedAt: Date
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: generatedAt,
            todayGrossSeconds: todayGrossSeconds,
            todayWallSeconds: todayWallSeconds,
            activeTimers: activeSegments.map { segment in
                let task = taskByID[segment.taskID]
                return WidgetTimerSnapshot(
                    id: segment.id,
                    taskID: segment.taskID,
                    title: task?.title ?? AppStrings.localized("task.deleted"),
                    path: taskParentPathByID[segment.taskID] ?? "",
                    startedAt: segment.startedAt,
                    colorHex: task?.colorHex,
                    iconName: task?.iconName
                )
            },
            recentTasks: recentTasks.prefix(3).map { task in
                WidgetRecentTaskSnapshot(
                    taskID: task.id,
                    title: task.title,
                    path: taskParentPathByID[task.id] ?? "",
                    colorHex: task.colorHex,
                    iconName: task.iconName
                )
            }
        )
    }
}
