import Foundation

enum AnalyticsRange: String, CaseIterable, Identifiable, Sendable {
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

/// Separates the selected calendar period from the two notions of "now" used
/// while evaluating it. `cutoff` clips tracked time, while `clockReference`
/// is the actual wall clock used to detect a genuine system-clock rewind.
nonisolated struct AnalyticsPeriodEvaluation: Hashable, Sendable {
    let interval: DateInterval
    let cutoff: Date
    let clockReference: Date
}

nonisolated extension AnalyticsRange {
    func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval? {
        switch self {
        case .today:
            return calendar.dateInterval(of: .day, for: date)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)
        case .month:
            return calendar.dateInterval(of: .month, for: date)
        }
    }

    func evaluation(
        referenceDate: Date,
        liveNow: Date,
        calendar: Calendar = .current
    ) -> AnalyticsPeriodEvaluation {
        let selectedInterval = interval(containing: referenceDate, calendar: calendar)
            ?? DateInterval(start: referenceDate, duration: 0)
        let cutoff: Date
        if selectedInterval.contains(liveNow) {
            cutoff = liveNow
        } else if selectedInterval.end <= liveNow {
            // DateInterval is half-open. Evaluating a completed period exactly
            // at its end preserves every instant before the boundary.
            cutoff = selectedInterval.end
        } else {
            // A future period must remain empty until its start arrives.
            cutoff = selectedInterval.start
        }
        return AnalyticsPeriodEvaluation(
            interval: selectedInterval,
            cutoff: cutoff,
            clockReference: liveNow
        )
    }

    func isCurrentPeriod(_ date: Date, liveNow: Date, calendar: Calendar = .current) -> Bool {
        guard let selected = interval(containing: date, calendar: calendar),
              let current = interval(containing: liveNow, calendar: calendar) else {
            return false
        }
        return selected.start == current.start
    }

    func date(byAdding value: Int, to date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .today:
            return calendar.date(byAdding: .day, value: value, to: date)
        case .week:
            return calendar.date(byAdding: .weekOfYear, value: value, to: date)
        case .month:
            return calendar.date(byAdding: .month, value: value, to: date)
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

nonisolated enum AnalyticsComparisonBasis: Equatable, Sendable {
    case matchedProgress
    case completePeriods
}

/// The exact calendar windows used by a comparison. A live or future period
/// compares only matching progress; a completed historical period compares the
/// two complete periods.
nonisolated struct AnalyticsComparisonWindow: Equatable, Sendable {
    let current: DateInterval
    let previous: DateInterval
    let basis: AnalyticsComparisonBasis
}

struct AnalyticsComparison {
    let window: AnalyticsComparisonWindow
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
    var grossMinutes: Double { Double(grossSeconds) / 60 }
    var wallMinutes: Double { Double(wallSeconds) / 60 }
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
