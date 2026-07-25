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

    static func isBounded(_ value: String, maximumUTF8Bytes: Int) -> Bool {
        value.utf8.count <= maximumUTF8Bytes
    }

    static func isFinite(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite
    }

    static func isValidStyleValue(_ value: String?) -> Bool {
        guard let value else { return true }
        return isBounded(value, maximumUTF8Bytes: maximumStyleValueBytes)
    }

    static func boundedUTF8Prefix(_ value: String, maximumUTF8Bytes: Int) -> String {
        guard value.utf8.count > maximumUTF8Bytes else { return value }
        var result = ""
        var byteCount = 0
        for character in value {
            let characterByteCount = String(character).utf8.count
            guard byteCount + characterByteCount <= maximumUTF8Bytes else { break }
            result.append(character)
            byteCount += characterByteCount
        }
        return result
    }

    static func boundedProjectedStyleValue(_ value: String?) -> String? {
        value.map {
            boundedUTF8Prefix($0, maximumUTF8Bytes: maximumProjectedStyleValueBytes)
        }
    }

    static func textByteCount(
        title: String,
        path: String,
        colorHex: String?,
        iconName: String?
    ) -> Int {
        title.utf8.count + path.utf8.count +
            (colorHex?.utf8.count ?? 0) + (iconName?.utf8.count ?? 0)
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
        generatedAt = widgetSnapshot.generatedAt
        todayGrossSeconds = widgetSnapshot.todayGrossSeconds
        todayWallSeconds = widgetSnapshot.todayWallSeconds
        activeTimers = widgetSnapshot.activeTimers.map {
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
        recentTasks = widgetSnapshot.recentTasks.map {
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

    func isAtLeastAsRecent(as other: WatchStateSnapshot) -> Bool {
        generatedAt >= other.generatedAt
    }

    func isValid(at now: Date) -> Bool {
        let quickStartRanks = recentTasks.compactMap(\.quickStartRank)
        let allTasksRanks = recentTasks.compactMap(\.allTasksRank)
        let hasValidQuickStartRanks = quickStartRanks.isEmpty ||
            Set(quickStartRanks) == Set(0 ..< quickStartRanks.count)
        let hasValidAllTasksRanks = allTasksRanks.isEmpty ||
            (
                allTasksRanks.count == recentTasks.count &&
                    Set(allTasksRanks) == Set(0 ..< recentTasks.count)
            )
        let textByteCount = activeTimers.reduce(into: 0) { total, timer in
            total += WatchTransportLimits.textByteCount(
                title: timer.title,
                path: timer.path,
                colorHex: timer.colorHex,
                iconName: timer.iconName
            )
        } + recentTasks.reduce(into: 0) { total, task in
            total += WatchTransportLimits.textByteCount(
                title: task.title,
                path: task.path,
                colorHex: task.colorHex,
                iconName: task.iconName
            )
        }
        guard WatchTransportLimits.isFinite(now),
              WatchTransportLimits.isFinite(generatedAt),
              generatedAt.timeIntervalSince(now) <= WatchTransportLimits.maximumFutureClockSkew,
              (0 ... WatchTransportLimits.maximumSummarySeconds).contains(todayGrossSeconds),
              (0 ... WatchTransportLimits.maximumSummarySeconds).contains(todayWallSeconds),
              activeTimers.count <= WatchTransportLimits.maximumActiveTimers,
              recentTasks.count <= WatchTransportLimits.maximumRecentTasks,
              textByteCount <= WatchTransportLimits.maximumSnapshotTextBytes,
              activeTimers.allSatisfy({ $0.isStructurallyValid(relativeTo: generatedAt) }),
              recentTasks.allSatisfy(\.isStructurallyValid),
              Set(activeTimers.map(\.id)).count == activeTimers.count,
              Set(recentTasks.map(\.taskID)).count == recentTasks.count,
              hasValidQuickStartRanks,
              hasValidAllTasksRanks
        else {
            return false
        }
        return true
    }

    /// New watch builds restore the usage order from optional metadata while
    /// the wire array remains pinned-first for older watch builds.
    var allTasksByUsage: [WatchRecentTaskSnapshot] {
        Array(recentTasks.enumerated())
            .sorted { lhs, rhs in
                switch (lhs.element.allTasksRank, rhs.element.allTasksRank) {
                case let (lhsRank?, rhsRank?) where lhsRank != rhsRank:
                    lhsRank < rhsRank
                case (_?, nil):
                    true
                case (nil, _?):
                    false
                default:
                    lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }
}

nonisolated enum WatchSnapshotFreshness: Equatable, Sendable {
    case current
    case stale
}

nonisolated enum WatchTimerElapsedPresentation: Equatable, Sendable {
    case live(startedAt: Date)
    case frozen(seconds: Int)
}

nonisolated struct WatchActiveTimerSnapshot: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var taskID: UUID
    var title: String
    var path: String
    var startedAt: Date
    var colorHex: String?
    var iconName: String?

    func elapsedPresentation(
        for freshness: WatchSnapshotFreshness,
        generatedAt: Date
    ) -> WatchTimerElapsedPresentation {
        guard freshness != .current else {
            return .live(startedAt: startedAt)
        }
        let elapsed = generatedAt.timeIntervalSince(startedAt)
        guard elapsed.isFinite else { return .frozen(seconds: 0) }
        let boundedElapsed = min(
            max(0, elapsed),
            WatchTransportLimits.maximumActiveTimerAge
        )
        return .frozen(seconds: Int(boundedElapsed.rounded(.down)))
    }

    func isStructurallyValid(relativeTo generatedAt: Date) -> Bool {
        guard WatchTransportLimits.isFinite(startedAt),
              WatchTransportLimits.isFinite(generatedAt),
              WatchTransportLimits.isBounded(
                  title,
                  maximumUTF8Bytes: WatchTransportLimits.maximumTitleBytes
              ),
              WatchTransportLimits.isBounded(
                  path,
                  maximumUTF8Bytes: WatchTransportLimits.maximumPathBytes
              ),
              WatchTransportLimits.isValidStyleValue(colorHex),
              WatchTransportLimits.isValidStyleValue(iconName)
        else {
            return false
        }
        let age = generatedAt.timeIntervalSince(startedAt)
        return age.isFinite &&
            age >= -WatchTransportLimits.maximumFutureClockSkew &&
            age <= WatchTransportLimits.maximumActiveTimerAge
    }
}

nonisolated struct WatchRecentTaskSnapshot: Codable, Equatable, Identifiable, Sendable {
    var taskID: UUID
    var title: String
    var path: String
    var colorHex: String?
    var iconName: String?
    var quickStartRank: Int? = nil
    var allTasksRank: Int? = nil

    nonisolated var id: UUID {
        taskID
    }

    var isStructurallyValid: Bool {
        WatchTransportLimits.isBounded(
            title,
            maximumUTF8Bytes: WatchTransportLimits.maximumTitleBytes
        ) &&
            WatchTransportLimits.isBounded(
                path,
                maximumUTF8Bytes: WatchTransportLimits.maximumPathBytes
            ) &&
            WatchTransportLimits.isValidStyleValue(colorHex) &&
            WatchTransportLimits.isValidStyleValue(iconName) &&
            quickStartRank.map {
                (0 ..< WatchTransportLimits.maximumQuickStartTasks).contains($0)
            } != false &&
            allTasksRank.map {
                (0 ..< WatchTransportLimits.maximumRecentTasks).contains($0)
            } != false
    }
}
