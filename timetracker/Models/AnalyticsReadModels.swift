import Foundation

enum AnalyticsRange: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "Week"
    case month = "Month"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .today:
            return AppStrings.localized("analytics.range.today")
        case .week:
            return AppStrings.localized("analytics.range.week")
        case .month:
            return AppStrings.localized("analytics.range.month")
        }
    }
}

struct AnalyticsOverview {
    let grossSeconds: Int
    let wallSeconds: Int
    let overlapSeconds: Int
    let pomodoroCount: Int
    let averageFocusSeconds: Int
}

struct AnalyticsComparison {
    let currentGrossSeconds: Int
    let previousGrossSeconds: Int
    let currentWallSeconds: Int
    let previousWallSeconds: Int

    var grossDeltaSeconds: Int {
        currentGrossSeconds - previousGrossSeconds
    }

    var wallDeltaSeconds: Int {
        currentWallSeconds - previousWallSeconds
    }

    var grossPercentChange: Double? {
        percentChange(current: currentGrossSeconds, previous: previousGrossSeconds)
    }

    var wallPercentChange: Double? {
        percentChange(current: currentWallSeconds, previous: previousWallSeconds)
    }

    private func percentChange(current: Int, previous: Int) -> Double? {
        guard previous > 0 else { return current > 0 ? 1 : nil }
        return Double(current - previous) / Double(previous)
    }
}

struct AnalyticsRhythm {
    let activeDayCount: Int
    let dailyAverageGrossSeconds: Int
    let peakHour: Int?
    let peakHourSeconds: Int
    let longestContinuousSeconds: Int
    let averageSegmentSeconds: Int
    let medianSegmentSeconds: Int
    let segmentCount: Int
}

struct AnalyticsQuality {
    let overlapRatio: Double
    let switchCount: Int
    let shortSegmentCount: Int
    let shortSegmentRatio: Double
    let averageSegmentSeconds: Int
    let longestContinuousSeconds: Int
}

struct AnalyticsInsight: Identifiable {
    enum Severity: String {
        case positive
        case neutral
        case warning
        case critical
    }

    let id: String
    let title: String
    let value: String
    let body: String
    let severity: Severity
    let taskID: UUID?
}

struct DailyAnalyticsPoint: Identifiable {
    let date: Date
    let grossSeconds: Int
    let wallSeconds: Int
    let label: String

    var id: Date { date }
}

struct HourlyAnalyticsPoint: Identifiable {
    let hour: Int
    let grossSeconds: Int
    let wallSeconds: Int

    var id: Int { hour }

    var label: String {
        hour == 0 ? "00" : "\(hour)"
    }
}

struct HourTaskActivity: Identifiable, Equatable {
    let hour: Int
    let slices: [HourTaskSlice]

    var id: Int { hour }
    var totalSeconds: Int { slices.reduce(0) { $0 + $1.seconds } }
}

struct HourTaskSlice: Identifiable, Equatable {
    let taskID: UUID
    let title: String
    let symbolName: String
    let colorHex: String
    let seconds: Int

    var id: UUID { taskID }
}

struct AnalyticsTimelineSnapshot: Equatable {
    let entries: [AnalyticsTimelineEntry]
    let displayInterval: DateInterval?
    let axisCompression: TimelineAxisCompression?

    static let empty = AnalyticsTimelineSnapshot(entries: [], displayInterval: nil, axisCompression: nil)

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

struct AnalyticsSnapshotRequest: Hashable {
    let range: AnalyticsRange
    let snapshotDate: Date
}

extension AnalyticsSnapshot {
    static func empty(range: AnalyticsRange) -> AnalyticsSnapshot {
        AnalyticsSnapshot(
            range: range,
            overview: AnalyticsOverview(grossSeconds: 0, wallSeconds: 0, overlapSeconds: 0, pomodoroCount: 0, averageFocusSeconds: 0),
            comparison: AnalyticsComparison(currentGrossSeconds: 0, previousGrossSeconds: 0, currentWallSeconds: 0, previousWallSeconds: 0),
            rhythm: AnalyticsRhythm(activeDayCount: 0, dailyAverageGrossSeconds: 0, peakHour: nil, peakHourSeconds: 0, longestContinuousSeconds: 0, averageSegmentSeconds: 0, medianSegmentSeconds: 0, segmentCount: 0),
            quality: AnalyticsQuality(overlapRatio: 0, switchCount: 0, shortSegmentCount: 0, shortSegmentRatio: 0, averageSegmentSeconds: 0, longestContinuousSeconds: 0),
            insights: [],
            daily: [],
            todayActivity: [],
            timeline: .empty,
            taskBreakdown: [],
            rootBreakdown: [],
            categoryBreakdown: [],
            overlaps: [],
            rangeSegments: []
        )
    }
}

struct OverlapAnalyticsPoint: Identifiable {
    let start: Date
    let end: Date
    let firstTitle: String
    let secondTitle: String

    var id: String {
        "\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))-\(firstTitle)-\(secondTitle)"
    }

    var durationSeconds: Int {
        max(0, Int(end.timeIntervalSince(start)))
    }
}
