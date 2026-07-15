import Foundation

nonisolated enum WidgetSnapshotLimits {
    static let maximumEncodedBytes = 256 * 1_024
    static let maximumFutureClockSkew: TimeInterval = 5 * 60
    static let maximumActiveTimerAge: TimeInterval = 10 * 366 * 24 * 60 * 60
    static let maximumSummarySeconds = 10 * 366 * 24 * 60 * 60
    static let maximumActiveTimers = 64
    static let maximumRecentTasks = 64
    static let maximumTitleBytes = 4 * 1_024
    static let maximumPathBytes = 16 * 1_024
    static let maximumStyleValueBytes = 256

    static func isFinite(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite
    }

    static func isBounded(_ value: String, maximumUTF8Bytes: Int) -> Bool {
        value.utf8.count <= maximumUTF8Bytes
    }

    static func isValidStyleValue(_ value: String?) -> Bool {
        guard let value else { return true }
        return isBounded(value, maximumUTF8Bytes: maximumStyleValueBytes)
    }
}

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

    nonisolated func isValid(at now: Date) -> Bool {
        guard WidgetSnapshotLimits.isFinite(now),
              WidgetSnapshotLimits.isFinite(generatedAt),
              generatedAt.timeIntervalSince(now) <= WidgetSnapshotLimits.maximumFutureClockSkew,
              (0...WidgetSnapshotLimits.maximumSummarySeconds).contains(todayGrossSeconds),
              (0...WidgetSnapshotLimits.maximumSummarySeconds).contains(todayWallSeconds),
              activeTimers.count <= WidgetSnapshotLimits.maximumActiveTimers,
              recentTasks.count <= WidgetSnapshotLimits.maximumRecentTasks,
              activeTimers.allSatisfy({ $0.isStructurallyValid(relativeTo: generatedAt) }),
              recentTasks.allSatisfy(\.isStructurallyValid),
              Set(activeTimers.map(\.id)).count == activeTimers.count,
              Set(recentTasks.map(\.taskID)).count == recentTasks.count else {
            return false
        }
        return true
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

    nonisolated func isStructurallyValid(relativeTo generatedAt: Date) -> Bool {
        guard WidgetSnapshotLimits.isFinite(startedAt),
              WidgetSnapshotLimits.isFinite(generatedAt),
              WidgetSnapshotLimits.isBounded(
                title,
                maximumUTF8Bytes: WidgetSnapshotLimits.maximumTitleBytes
              ),
              WidgetSnapshotLimits.isBounded(
                path,
                maximumUTF8Bytes: WidgetSnapshotLimits.maximumPathBytes
              ),
              WidgetSnapshotLimits.isValidStyleValue(colorHex),
              WidgetSnapshotLimits.isValidStyleValue(iconName) else {
            return false
        }
        let age = generatedAt.timeIntervalSince(startedAt)
        return age.isFinite &&
            age >= -WidgetSnapshotLimits.maximumFutureClockSkew &&
            age <= WidgetSnapshotLimits.maximumActiveTimerAge
    }
}

nonisolated struct WidgetRecentTaskSnapshot: Codable, Equatable, Identifiable, Sendable {
    var taskID: UUID
    var title: String
    var path: String
    var colorHex: String?
    var iconName: String?

    var id: UUID { taskID }

    nonisolated var isStructurallyValid: Bool {
        WidgetSnapshotLimits.isBounded(
            title,
            maximumUTF8Bytes: WidgetSnapshotLimits.maximumTitleBytes
        ) &&
            WidgetSnapshotLimits.isBounded(
                path,
                maximumUTF8Bytes: WidgetSnapshotLimits.maximumPathBytes
            ) &&
            WidgetSnapshotLimits.isValidStyleValue(colorHex) &&
            WidgetSnapshotLimits.isValidStyleValue(iconName)
    }
}
