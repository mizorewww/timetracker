import Foundation

nonisolated enum WidgetSnapshotLimits {
    static let maximumEncodedBytes = 256 * 1024
    static let maximumFutureClockSkew: TimeInterval = 5 * 60
    static let maximumActiveTimerAge: TimeInterval = 10 * 366 * 24 * 60 * 60
    static let maximumSummarySeconds = 10 * 366 * 24 * 60 * 60
    static let maximumActiveTimers = 64
    static let maximumRecentTasks = 64
    static let maximumTitleBytes = 4 * 1024
    static let maximumPathBytes = 16 * 1024
    static let maximumStyleValueBytes = 256
    static let maximumProjectedTitleBytes = 512
    static let maximumProjectedPathBytes = 1024
    static let maximumProjectedStyleValueBytes = 128
    static let maximumSnapshotTextBytes = 128 * 1024

    static func boundedProjectedStyleValue(_ value: String?) -> String? {
        SystemSurfaceTextBounds.boundedProjectedStyleValue(
            value,
            maximumUTF8Bytes: maximumProjectedStyleValueBytes
        )
    }

    static func boundedTimerStart(_ startedAt: Date, generatedAt: Date) -> Date {
        SystemSurfaceTextBounds.boundedTimerStart(
            startedAt,
            generatedAt: generatedAt,
            maximumActiveTimerAge: maximumActiveTimerAge
        )
    }
}

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
        guard SystemSurfaceTextBounds.isFinite(now),
              SystemSurfaceTextBounds.isFinite(generatedAt)
        else {
            return .clockAdjusted
        }
        if generatedAt.timeIntervalSince(now) > WidgetSnapshotLimits.maximumFutureClockSkew {
            return .clockAdjusted
        }
        return now.timeIntervalSince(generatedAt) > threshold ? .stale : .current
    }

    nonisolated var isStructurallyValid: Bool {
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
        guard SystemSurfaceTextBounds.isFinite(generatedAt),
              (0 ... WidgetSnapshotLimits.maximumSummarySeconds).contains(todayGrossSeconds),
              (0 ... WidgetSnapshotLimits.maximumSummarySeconds).contains(todayWallSeconds),
              activeTimers.count <= WidgetSnapshotLimits.maximumActiveTimers,
              recentTasks.count <= WidgetSnapshotLimits.maximumRecentTasks,
              textByteCount <= WidgetSnapshotLimits.maximumSnapshotTextBytes,
              activeTimers.allSatisfy({
                  $0.isStructurallyValid(
                      relativeTo: generatedAt,
                      maximumTitleBytes: WidgetSnapshotLimits.maximumTitleBytes,
                      maximumPathBytes: WidgetSnapshotLimits.maximumPathBytes,
                      maximumStyleValueBytes: WidgetSnapshotLimits.maximumStyleValueBytes,
                      maximumFutureClockSkew: WidgetSnapshotLimits.maximumFutureClockSkew,
                      maximumActiveTimerAge: WidgetSnapshotLimits.maximumActiveTimerAge
                  )
              }),
              recentTasks.allSatisfy({
                  $0.isStructurallyValid(
                      maximumTitleBytes: WidgetSnapshotLimits.maximumTitleBytes,
                      maximumPathBytes: WidgetSnapshotLimits.maximumPathBytes,
                      maximumStyleValueBytes: WidgetSnapshotLimits.maximumStyleValueBytes
                  )
              }),
              Set(activeTimers.map(\.id)).count == activeTimers.count,
              Set(recentTasks.map(\.taskID)).count == recentTasks.count
        else {
            return false
        }
        return true
    }
}

nonisolated enum WidgetSnapshotFreshness: Equatable, Sendable {
    case current
    case stale
    case clockAdjusted
}
