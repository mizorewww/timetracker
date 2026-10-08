import Foundation

nonisolated enum LiveActivityProjectionLimits {
    static let maximumTitleUTF8Bytes = 512
    static let maximumPathUTF8Bytes = 768
    static let maximumIconUTF8Bytes = 128
    static let maximumColorUTF8Bytes = 16

    static func boundedUTF8Prefix(
        _ value: String,
        maximumUTF8Bytes: Int
    ) -> String {
        SystemSurfaceTextBounds.boundedUTF8Prefix(
            value,
            maximumUTF8Bytes: maximumUTF8Bytes
        )
    }
}

#if os(iOS) && canImport(ActivityKit)
import ActivityKit

nonisolated struct TimeTrackingActivityAttributes: ActivityAttributes, Sendable {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
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
