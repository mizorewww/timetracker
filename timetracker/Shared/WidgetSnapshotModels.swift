import Foundation

nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    nonisolated static let staleAfter: TimeInterval = 15 * 60

    var generatedAt: Date
    var todayGrossSeconds: Int
    var todayWallSeconds: Int
    var activeTimers: [WidgetTimerSnapshot]
    var recentTasks: [WidgetRecentTaskSnapshot] = []

    static var empty: WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: Date(),
            todayGrossSeconds: 0,
            todayWallSeconds: 0,
            activeTimers: [],
            recentTasks: []
        )
    }

    nonisolated func freshness(
        at now: Date,
        staleAfter threshold: TimeInterval = WidgetSnapshot.staleAfter
    ) -> WidgetSnapshotFreshness {
        now.timeIntervalSince(generatedAt) > threshold ? .stale : .current
    }
}

nonisolated enum WidgetSnapshotFreshness: Equatable, Sendable {
    case current
    case stale
}

nonisolated struct WidgetTimerSnapshot: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var taskID: UUID
    var title: String
    var path: String
    var startedAt: Date
    var colorHex: String?
    var iconName: String?
}

nonisolated struct WidgetRecentTaskSnapshot: Codable, Equatable, Identifiable, Sendable {
    var taskID: UUID
    var title: String
    var path: String
    var colorHex: String?
    var iconName: String?

    var id: UUID { taskID }
}
