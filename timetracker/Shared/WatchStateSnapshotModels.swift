import Foundation

nonisolated enum WatchTransportLimits {
    /// Watch commands are immediate controls. A durable delivery that arrives
    /// later than this must ask the user to retry instead of acting silently.
    static let maximumCommandAge: TimeInterval = 30
    static let maximumFutureClockSkew: TimeInterval = 5 * 60
    static let maximumDeviceIDBytes = 256
    static let maximumFailureCodeBytes = 256
    static let maximumTitleBytes = 4 * 1_024
    static let maximumPathBytes = 16 * 1_024
    static let maximumStyleValueBytes = 256
    static let maximumActiveTimers = 64
    static let maximumRecentTasks = 256
    static let maximumSummarySeconds = 10 * 366 * 24 * 60 * 60
    static let maximumActiveTimerAge: TimeInterval = 10 * 366 * 24 * 60 * 60
    static let maximumIncomingCommands = 64
    static let maximumPersistedPendingCommands = 64
    static let maximumPersistedFailedCommands = 64
    static let maximumQueueEncodedBytes = 512 * 1_024

    static func isBounded(_ value: String, maximumUTF8Bytes: Int) -> Bool {
        value.utf8.count <= maximumUTF8Bytes
    }

    static func isFinite(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite
    }
}

nonisolated struct WatchStateSnapshot: Codable, Equatable, Sendable {
    static let staleAfter: TimeInterval = 15 * 60

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

    func freshness(
        at now: Date,
        staleAfter threshold: TimeInterval = WatchStateSnapshot.staleAfter
    ) -> WatchSnapshotFreshness {
        now.timeIntervalSince(generatedAt) > threshold ? .stale : .current
    }
}

nonisolated enum WatchSnapshotFreshness: Equatable, Sendable {
    case current
    case stale
}

nonisolated struct WatchActiveTimerSnapshot: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var taskID: UUID
    var title: String
    var path: String
    var startedAt: Date
    var colorHex: String?
    var iconName: String?
}

nonisolated struct WatchRecentTaskSnapshot: Codable, Equatable, Identifiable, Sendable {
    var taskID: UUID
    var title: String
    var path: String
    var colorHex: String?
    var iconName: String?

    nonisolated var id: UUID { taskID }
}
