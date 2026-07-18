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

nonisolated enum LiveActivityProjectionLimits {
    static let maximumTitleUTF8Bytes = 512
    static let maximumPathUTF8Bytes = 768
    static let maximumIconUTF8Bytes = 128
    static let maximumColorUTF8Bytes = 16

    static func boundedUTF8Prefix(
        _ value: String,
        maximumUTF8Bytes: Int
    ) -> String {
        guard value.utf8.count > maximumUTF8Bytes else { return value }

        var result = ""
        result.reserveCapacity(min(value.count, maximumUTF8Bytes))
        var byteCount = 0
        for character in value {
            let characterByteCount = String(character).utf8.count
            guard byteCount + characterByteCount <= maximumUTF8Bytes else { break }
            result.append(character)
            byteCount += characterByteCount
        }
        return result
    }
}

#if os(iOS) && canImport(ActivityKit)
import ActivityKit

nonisolated struct TimeTrackingActivityAttributes: ActivityAttributes, Sendable {
    public nonisolated struct ContentState: Codable, Hashable, Sendable {
        var taskTitle: String
        var taskPath: String
        var taskPathAbbreviated: String?
        var iconName: String
        var colorHex: String
        var startedAt: Date
        var additionalTimerCount: Int
    }

    var segmentID: String
    var taskID: String
}
#endif
