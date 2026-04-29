import Foundation

#if os(iOS) && canImport(ActivityKit)
import ActivityKit

struct TimeTrackingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
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
