import Foundation

struct WatchStateSnapshot: Codable, Equatable {
    var generatedAt: Date
    var todayGrossSeconds: Int
    var todayWallSeconds: Int
    var activeTimers: [WatchActiveTimerSnapshot]
    var recentTasks: [WatchRecentTaskSnapshot]

    nonisolated static var empty: WatchStateSnapshot {
        WatchStateSnapshot(
            generatedAt: Date(),
            todayGrossSeconds: 0,
            todayWallSeconds: 0,
            activeTimers: [],
            recentTasks: []
        )
    }

    nonisolated init(
        generatedAt: Date,
        todayGrossSeconds: Int,
        todayWallSeconds: Int,
        activeTimers: [WatchActiveTimerSnapshot],
        recentTasks: [WatchRecentTaskSnapshot]
    ) {
        self.generatedAt = generatedAt
        self.todayGrossSeconds = todayGrossSeconds
        self.todayWallSeconds = todayWallSeconds
        self.activeTimers = activeTimers
        self.recentTasks = recentTasks
    }

    nonisolated init(widgetSnapshot: WidgetSnapshot) {
        self.generatedAt = widgetSnapshot.generatedAt
        self.todayGrossSeconds = widgetSnapshot.todayGrossSeconds
        self.todayWallSeconds = widgetSnapshot.todayWallSeconds
        self.activeTimers = widgetSnapshot.activeTimers.map {
            WatchActiveTimerSnapshot(
                id: $0.id,
                taskID: $0.taskID,
                title: $0.title,
                path: $0.path,
                startedAt: $0.startedAt,
                colorHex: $0.colorHex,
                iconName: $0.iconName
            )
        }
        self.recentTasks = widgetSnapshot.recentTasks.map {
            WatchRecentTaskSnapshot(
                taskID: $0.taskID,
                title: $0.title,
                path: $0.path,
                colorHex: $0.colorHex,
                iconName: $0.iconName
            )
        }
    }
}

struct WatchActiveTimerSnapshot: Codable, Equatable, Identifiable {
    var id: UUID
    var taskID: UUID
    var title: String
    var path: String
    var startedAt: Date
    var colorHex: String?
    var iconName: String?
}

struct WatchRecentTaskSnapshot: Codable, Equatable, Identifiable {
    var taskID: UUID
    var title: String
    var path: String
    var colorHex: String?
    var iconName: String?

    nonisolated var id: UUID { taskID }
}
