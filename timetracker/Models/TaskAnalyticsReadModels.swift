import Foundation

struct TaskAnalyticsPoint: Identifiable {
    let taskID: UUID
    let title: String
    let path: String
    let colorHex: String?
    let iconName: String?
    let status: TaskStatus?
    let grossSeconds: Int
    let wallSeconds: Int

    var id: UUID { taskID }
}

struct AnalyticsGroupBreakdownPoint: Identifiable {
    enum GroupKind: String {
        case rootTask
        case category
    }

    let id: String
    let kind: GroupKind
    let title: String
    let subtitle: String
    let iconName: String
    let colorHex: String
    let grossSeconds: Int
    let wallSeconds: Int
}

struct TaskRecentRecordPoint: Identifiable {
    let id: UUID
    let taskID: UUID
    let title: String
    let path: String
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Int
}

struct TaskAnalyticsSnapshot {
    let taskID: UUID
    let range: AnalyticsRange
    let overview: AnalyticsOverview
    let comparison: AnalyticsComparison
    let rhythm: AnalyticsRhythm
    let quality: AnalyticsQuality
    let directSeconds: Int
    let descendantSeconds: Int
    let childBreakdown: [AnalyticsGroupBreakdownPoint]
    let daily: [DailyAnalyticsPoint]
    let recentRecords: [TaskRecentRecordPoint]
    let rangeSegments: [TimeSegment]
}
