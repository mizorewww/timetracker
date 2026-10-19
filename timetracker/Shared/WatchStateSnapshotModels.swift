import Foundation

nonisolated enum WatchTransportLimits {
    /// Watch commands are immediate controls; an older one is rejected so the
    /// user retries instead of the iPhone acting on a stale tap.
    static let maximumCommandAge: TimeInterval = 30
    static let maximumDeviceIDBytes = 256
    static let maximumFailureCodeBytes = 256
    static let maximumPendingCommands = 64
    static let maximumFailedCommands = 64
}

typealias WatchActiveTimerSnapshot = SystemSurfaceTimerSnapshot
typealias WatchRecentTaskSnapshot = SystemSurfaceRecentTaskSnapshot
typealias WatchTimerElapsedPresentation = SystemSurfaceTimerElapsedPresentation

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
        self.init(
            generatedAt: widgetSnapshot.generatedAt,
            todayGrossSeconds: widgetSnapshot.todayGrossSeconds,
            todayWallSeconds: widgetSnapshot.todayWallSeconds,
            activeTimers: widgetSnapshot.activeTimers,
            recentTasks: widgetSnapshot.recentTasks
        )
    }

    func freshness(
        at now: Date,
        staleAfter threshold: TimeInterval = WatchStateSnapshot.staleAfter
    ) -> WatchSnapshotFreshness {
        now.timeIntervalSince(generatedAt) > threshold ? .stale : .current
    }

    func isAtLeastAsRecent(as other: WatchStateSnapshot) -> Bool {
        generatedAt >= other.generatedAt
    }

    /// A snapshot stamped further ahead than the clock-skew allowance would
    /// otherwise shadow every newer one.
    func isPlausible(at now: Date) -> Bool {
        generatedAt.timeIntervalSince(now) <= SystemSurfaceLimits.maximumFutureClockSkew
    }
}

nonisolated enum WatchSnapshotFreshness: Equatable, Sendable {
    case current
    case stale
}
