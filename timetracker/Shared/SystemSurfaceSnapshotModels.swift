import Foundation

/// The single bound table for every Widget and Watch snapshot payload
/// (AD-004). Projection truncates each field to its cap once; decoding only
/// checks the encoded size, because every field is bounded by construction.
nonisolated enum SystemSurfaceLimits {
    static let maximumEncodedBytes = 256 * 1024
    /// Projection budget for all strings of one snapshot. Keeps the encoded
    /// payload well under `maximumEncodedBytes`.
    static let maximumSnapshotTextBytes = 128 * 1024
    static let maximumFutureClockSkew: TimeInterval = 5 * 60
    static let maximumActiveTimerAge: TimeInterval = 10 * 366 * 24 * 60 * 60
    static let maximumSummarySeconds = 10 * 366 * 24 * 60 * 60
    static let maximumActiveTimers = 64
    static let maximumWidgetRecentTasks = 3
    static let maximumWatchTasks = 256
    static let maximumQuickStartTasks = 24
    static let maximumTitleBytes = 512
    static let maximumPathBytes = 1024
    static let maximumStyleValueBytes = 128

    static func boundedTitle(_ value: String) -> String {
        SystemSurfaceTextBounds.boundedUTF8Prefix(value, maximumUTF8Bytes: maximumTitleBytes)
    }

    static func boundedPath(_ value: String) -> String {
        SystemSurfaceTextBounds.boundedUTF8Prefix(value, maximumUTF8Bytes: maximumPathBytes)
    }

    static func boundedStyleValue(_ value: String?) -> String? {
        value.map {
            SystemSurfaceTextBounds.boundedUTF8Prefix($0, maximumUTF8Bytes: maximumStyleValueBytes)
        }
    }

    static func boundedSummarySeconds(_ seconds: Int) -> Int {
        min(max(0, seconds), maximumSummarySeconds)
    }

    static func boundedTimerStart(_ startedAt: Date, generatedAt: Date) -> Date {
        min(
            max(startedAt, generatedAt.addingTimeInterval(-maximumActiveTimerAge)),
            generatedAt
        )
    }
}

/// Shared DTO home for the widget and watch snapshot payloads, so both
/// surfaces decode and encode identical wire shapes.
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
        generatedAt: Date
    ) -> SystemSurfaceTimerElapsedPresentation {
        if isCurrent {
            return .live(startedAt: startedAt)
        }
        let elapsed = generatedAt.timeIntervalSince(startedAt)
        let boundedElapsed = min(max(0, elapsed), SystemSurfaceLimits.maximumActiveTimerAge)
        return .frozen(seconds: Int(boundedElapsed.rounded(.down)))
    }

    var textByteCount: Int {
        SystemSurfaceTextBounds.textByteCount(
            title: title,
            path: path,
            colorHex: colorHex,
            iconName: iconName
        )
    }
}

nonisolated struct SystemSurfaceRecentTaskSnapshot: Codable, Equatable, Identifiable, Sendable {
    var taskID: UUID
    var title: String
    var path: String
    var colorHex: String?
    var iconName: String?
    /// Position on the Watch Quick Start page; `nil` for tasks not offered there.
    var quickStartRank: Int? = nil

    nonisolated var id: UUID {
        taskID
    }

    var textByteCount: Int {
        SystemSurfaceTextBounds.textByteCount(
            title: title,
            path: path,
            colorHex: colorHex,
            iconName: iconName
        )
    }
}
