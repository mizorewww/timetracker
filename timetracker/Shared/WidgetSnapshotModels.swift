import Foundation

typealias WidgetTimerSnapshot = SystemSurfaceTimerSnapshot
typealias WidgetRecentTaskSnapshot = SystemSurfaceRecentTaskSnapshot
typealias WidgetTimerElapsedPresentation = SystemSurfaceTimerElapsedPresentation

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
        if generatedAt.timeIntervalSince(now) > SystemSurfaceLimits.maximumFutureClockSkew {
            return .clockAdjusted
        }
        return now.timeIntervalSince(generatedAt) > threshold ? .stale : .current
    }
}

nonisolated enum WidgetSnapshotFreshness: Equatable, Sendable {
    case current
    case stale
    case clockAdjusted
}
