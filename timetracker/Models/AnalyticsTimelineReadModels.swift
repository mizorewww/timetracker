import Foundation

struct AnalyticsTimelineSnapshot: Equatable {
    let entries: [AnalyticsTimelineEntry]
    let displayInterval: DateInterval?
    let axisCompression: TimelineAxisCompression?

    static let empty = AnalyticsTimelineSnapshot(
        entries: [],
        displayInterval: nil,
        axisCompression: nil
    )

    var laneCount: Int {
        (entries.map(\.lane).max() ?? -1) + 1
    }
}

struct AnalyticsTimelineEntry: Identifiable, Equatable {
    let id: UUID
    let taskID: UUID
    let title: String
    let path: String
    let iconName: String
    let colorHex: String
    let startedAt: Date
    let endedAt: Date
    let lane: Int
    let labelIndex: Int
    let interval: DateInterval

    var durationSeconds: Int {
        max(0, Int(endedAt.timeIntervalSince(startedAt)))
    }
}
