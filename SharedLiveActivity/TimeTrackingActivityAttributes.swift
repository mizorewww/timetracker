import Foundation

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
