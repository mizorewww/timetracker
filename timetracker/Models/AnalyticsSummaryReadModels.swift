import Foundation

nonisolated struct AnalyticsOverview: Sendable {
    let grossSeconds: Int
    let wallSeconds: Int
    let overlapSeconds: Int
    let pomodoroCount: Int
    let averageFocusSeconds: Int
}

nonisolated struct AnalyticsComparison: Sendable {
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
}

nonisolated struct AnalyticsRhythm: Sendable {
    let activeDayCount: Int
    let dailyAverageGrossSeconds: Int
    let peakHour: Int?
    let peakHourSeconds: Int
    let longestContinuousSeconds: Int
    let averageSegmentSeconds: Int
    let medianSegmentSeconds: Int
    let segmentCount: Int
}

nonisolated struct AnalyticsQuality: Sendable {
    let overlapRatio: Double
    let switchCount: Int
    let shortSegmentCount: Int
    let shortSegmentRatio: Double
    let averageSegmentSeconds: Int
    let longestContinuousSeconds: Int
}

nonisolated struct AnalyticsInsight: Identifiable, Sendable {
    enum Severity: String, Sendable {
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

nonisolated struct DailyAnalyticsPoint: Identifiable, Sendable {
    let date: Date
    let grossSeconds: Int
    let wallSeconds: Int
    let label: String

    var id: Date {
        date
    }

    var grossMinutes: Double {
        Double(grossSeconds) / 60
    }

    var wallMinutes: Double {
        Double(wallSeconds) / 60
    }
}

nonisolated struct HourTaskActivity: Identifiable, Equatable, Sendable {
    let hour: Int
    let slices: [HourTaskSlice]

    var id: Int {
        hour
    }

    var totalSeconds: Int {
        slices.reduce(0) { $0 + $1.seconds }
    }
}

nonisolated struct HourTaskSlice: Identifiable, Equatable, Sendable {
    let taskID: UUID
    let title: String
    let symbolName: String
    let colorHex: String
    let seconds: Int

    var id: UUID {
        taskID
    }
}
