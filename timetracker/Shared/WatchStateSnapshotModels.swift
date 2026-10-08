import Foundation

nonisolated enum WatchTransportLimits {
    /// Watch commands are immediate controls. A durable delivery that arrives
    /// later than this must ask the user to retry instead of acting silently.
    static let maximumCommandAge: TimeInterval = 30
    static let maximumFutureClockSkew: TimeInterval = 5 * 60
    static let maximumDeviceIDBytes = 256
    static let maximumFailureCodeBytes = 256
    static let maximumTitleBytes = 4 * 1024
    static let maximumPathBytes = 16 * 1024
    static let maximumStyleValueBytes = 256
    static let maximumProjectedTitleBytes = 512
    static let maximumProjectedPathBytes = 1024
    static let maximumProjectedStyleValueBytes = 128
    static let maximumSnapshotTextBytes = 128 * 1024
    static let maximumActiveTimers = 64
    static let maximumRecentTasks = 256
    static let maximumQuickStartTasks = 24
    static let legacyQuickStartTaskLimit = 4
    static let maximumSummarySeconds = 10 * 366 * 24 * 60 * 60
    static let maximumActiveTimerAge: TimeInterval = 10 * 366 * 24 * 60 * 60
    static let maximumIncomingCommands = 64
    static let maximumPersistedPendingCommands = 64
    static let maximumPersistedFailedCommands = 64
    static let maximumQueueEncodedBytes = 512 * 1024

    static func boundedProjectedStyleValue(_ value: String?) -> String? {
        SystemSurfaceTextBounds.boundedProjectedStyleValue(
            value,
            maximumUTF8Bytes: maximumProjectedStyleValueBytes
        )
    }
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

    func isValid(at now: Date) -> Bool {
        let textByteCount = activeTimers.reduce(into: 0) { total, timer in
            total += SystemSurfaceTextBounds.textByteCount(
                title: timer.title,
                path: timer.path,
                colorHex: timer.colorHex,
                iconName: timer.iconName
            )
        } + recentTasks.reduce(into: 0) { total, task in
            total += SystemSurfaceTextBounds.textByteCount(
                title: task.title,
                path: task.path,
                colorHex: task.colorHex,
                iconName: task.iconName
            )
        }
        guard SystemSurfaceTextBounds.isFinite(now),
              SystemSurfaceTextBounds.isFinite(generatedAt),
              generatedAt.timeIntervalSince(now) <= WatchTransportLimits.maximumFutureClockSkew,
              (0 ... WatchTransportLimits.maximumSummarySeconds).contains(todayGrossSeconds),
              (0 ... WatchTransportLimits.maximumSummarySeconds).contains(todayWallSeconds),
              activeTimers.count <= WatchTransportLimits.maximumActiveTimers,
              recentTasks.count <= WatchTransportLimits.maximumRecentTasks,
              textByteCount <= WatchTransportLimits.maximumSnapshotTextBytes,
              activeTimers.allSatisfy({
                  $0.isStructurallyValid(
                      relativeTo: generatedAt,
                      maximumTitleBytes: WatchTransportLimits.maximumTitleBytes,
                      maximumPathBytes: WatchTransportLimits.maximumPathBytes,
                      maximumStyleValueBytes: WatchTransportLimits.maximumStyleValueBytes,
                      maximumFutureClockSkew: WatchTransportLimits.maximumFutureClockSkew,
                      maximumActiveTimerAge: WatchTransportLimits.maximumActiveTimerAge
                  )
              }),
              recentTasks.allSatisfy({
                  $0.isStructurallyValid(
                      maximumTitleBytes: WatchTransportLimits.maximumTitleBytes,
                      maximumPathBytes: WatchTransportLimits.maximumPathBytes,
                      maximumStyleValueBytes: WatchTransportLimits.maximumStyleValueBytes
                  ) && $0.hasValidRanks(
                      maximumQuickStartTasks: WatchTransportLimits.maximumQuickStartTasks,
                      maximumRecentTasks: WatchTransportLimits.maximumRecentTasks
                  )
              }),
              Set(activeTimers.map(\.id)).count == activeTimers.count,
              Set(recentTasks.map(\.taskID)).count == recentTasks.count
        else {
            return false
        }
        return true
    }

    var allTasksByUsage: [WatchRecentTaskSnapshot] {
        WatchRecentTaskSnapshot.orderedByUsage(recentTasks)
    }
}

nonisolated enum WatchSnapshotFreshness: Equatable, Sendable {
    case current
    case stale
}
