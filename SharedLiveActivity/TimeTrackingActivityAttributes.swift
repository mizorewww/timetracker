import Foundation

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
    }

    var segmentID: String
    var taskID: String
}
#endif
