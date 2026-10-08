import Foundation

/// Shared DTO home for the widget and watch snapshot payloads. The per-surface
/// limit constants stay in each surface's limits enum (AD-004); this file only
/// hosts the row types so widget and watch decode/encode identical wire shapes.
nonisolated enum SystemSurfaceTimerElapsedPresentation: Equatable, Sendable {
    case live(startedAt: Date)
    case frozen(seconds: Int)
}

nonisolated struct SystemSurfaceTimerSnapshot: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var taskID: UUID
    var title: String
    var path: String
    var startedAt: Date
    var colorHex: String?
    var iconName: String?

    nonisolated func elapsedPresentation(
        isCurrent: Bool,
        generatedAt: Date,
        maximumActiveTimerAge: TimeInterval
    ) -> SystemSurfaceTimerElapsedPresentation {
        if isCurrent {
            return .live(startedAt: startedAt)
        }
        let elapsed = generatedAt.timeIntervalSince(startedAt)
        guard elapsed.isFinite else { return .frozen(seconds: 0) }
        let boundedElapsed = min(max(0, elapsed), maximumActiveTimerAge)
        return .frozen(seconds: Int(boundedElapsed.rounded(.down)))
    }

    nonisolated func isStructurallyValid(
        relativeTo generatedAt: Date,
        maximumTitleBytes: Int,
        maximumPathBytes: Int,
        maximumStyleValueBytes: Int,
        maximumFutureClockSkew: TimeInterval,
        maximumActiveTimerAge: TimeInterval
    ) -> Bool {
        guard SystemSurfaceTextBounds.isFinite(startedAt),
              SystemSurfaceTextBounds.isFinite(generatedAt),
              SystemSurfaceTextBounds.isBounded(
                  title,
                  maximumUTF8Bytes: maximumTitleBytes
              ),
              SystemSurfaceTextBounds.isBounded(
                  path,
                  maximumUTF8Bytes: maximumPathBytes
              ),
              SystemSurfaceTextBounds.isValidStyleValue(
                  colorHex,
                  maximumUTF8Bytes: maximumStyleValueBytes
              ),
              SystemSurfaceTextBounds.isValidStyleValue(
                  iconName,
                  maximumUTF8Bytes: maximumStyleValueBytes
              )
        else {
            return false
        }
        let age = generatedAt.timeIntervalSince(startedAt)
        return age.isFinite &&
            age >= -maximumFutureClockSkew &&
            age <= maximumActiveTimerAge
    }
}

nonisolated struct SystemSurfaceRecentTaskSnapshot: Codable, Equatable, Identifiable, Sendable {
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

    nonisolated func isStructurallyValid(
        maximumTitleBytes: Int,
        maximumPathBytes: Int,
        maximumStyleValueBytes: Int
    ) -> Bool {
        SystemSurfaceTextBounds.isBounded(
            title,
            maximumUTF8Bytes: maximumTitleBytes
        ) &&
            SystemSurfaceTextBounds.isBounded(
                path,
                maximumUTF8Bytes: maximumPathBytes
            ) &&
            SystemSurfaceTextBounds.isValidStyleValue(
                colorHex,
                maximumUTF8Bytes: maximumStyleValueBytes
            ) &&
            SystemSurfaceTextBounds.isValidStyleValue(
                iconName,
                maximumUTF8Bytes: maximumStyleValueBytes
            )
    }

    nonisolated func hasValidRanks(
        maximumQuickStartTasks: Int,
        maximumRecentTasks: Int
    ) -> Bool {
        quickStartRank.map {
            (0 ..< maximumQuickStartTasks).contains($0)
        } != false &&
            allTasksRank.map {
                (0 ..< maximumRecentTasks).contains($0)
            } != false
    }

    /// New watch builds restore the usage order from optional metadata while
    /// the wire array remains pinned-first for older watch builds.
    nonisolated static func orderedByUsage(
        _ tasks: [SystemSurfaceRecentTaskSnapshot]
    ) -> [SystemSurfaceRecentTaskSnapshot] {
        Array(tasks.enumerated())
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
