import Foundation

nonisolated enum LiveActivityElapsedPresentation: Equatable, Sendable {
    case live(startedAt: Date)
    case frozen(seconds: Int)
}

nonisolated enum LiveActivityTimingPolicy {
    /// Apple's Live Activity guidance treats activities longer than eight hours
    /// as outside the intended glanceable lifecycle. Use one shared boundary for
    /// both ActivityKit freshness and the extension's frozen elapsed value.
    static let staleAfter: TimeInterval = 8 * 60 * 60

    static func staleDate(for startedAt: Date) -> Date {
        startedAt.addingTimeInterval(staleAfter)
    }

    static func elapsedPresentation(
        startedAt: Date,
        isStale: Bool
    ) -> LiveActivityElapsedPresentation {
        isStale
            ? .frozen(seconds: Int(staleAfter))
            : .live(startedAt: startedAt)
    }
}

#if os(iOS) && canImport(ActivityKit)
import ActivityKit

nonisolated struct TimeTrackingActivityAttributes: ActivityAttributes, Sendable {
    public nonisolated struct ContentState: Codable, Hashable, Sendable {
        var taskTitle: String
        var taskPath: String
        var iconName: String
        var colorHex: String
        var startedAt: Date
        var additionalTimerCount: Int
    }

    var taskID: String
}
#endif
