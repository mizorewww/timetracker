import Foundation

nonisolated enum ActivityHeatmapPeriod: String, CaseIterable, Identifiable, Equatable, Hashable, Sendable {
    case oneMonth
    case threeMonths
    case sixMonths
    case oneYear

    static let standard = ActivityHeatmapPeriod.oneYear

    var id: String {
        rawValue
    }

    var weekCount: Int {
        switch self {
        case .oneMonth:
            5
        case .threeMonths:
            14
        case .sixMonths:
            27
        case .oneYear:
            53
        }
    }
}

nonisolated enum ActivityHeatmapIntensity: Int, CaseIterable, Equatable, Sendable {
    case none
    case low
    case medium
    case high
    case maximum

    init(value: Int, referenceValue: Int) {
        guard value > 0, referenceValue > 0 else {
            self = .none
            return
        }
        let boundedValue = min(Int64(value), Int64(referenceValue))
        let reference = Int64(referenceValue)
        let level = min(4, max(1, (boundedValue * 4 + reference - 1) / reference))
        self = ActivityHeatmapIntensity(rawValue: Int(level)) ?? .maximum
    }
}

nonisolated enum ActivityHeatmapMetric: Equatable, Sendable {
    case trackedDuration
    case checklistCompletions
    case quantity(unitLabel: String)
}

nonisolated struct ActivityHeatmapDay: Identifiable, Equatable, Sendable {
    let date: Date
    let value: Int
    let referenceValue: Int
    let intensity: ActivityHeatmapIntensity
    let isFuture: Bool
    let isToday: Bool

    var id: Date {
        date
    }
}

nonisolated struct ActivityHeatmapWeek: Identifiable, Equatable, Sendable {
    let startDate: Date
    let days: [ActivityHeatmapDay]

    var id: Date {
        startDate
    }
}

nonisolated struct TaskActivityHeatmapSnapshot: Identifiable, Equatable, Sendable {
    let taskID: UUID
    let title: String
    let iconName: String
    let colorHex: String
    let metric: ActivityHeatmapMetric
    let interval: DateInterval
    let today: Date
    let weeks: [ActivityHeatmapWeek]
    let totalValue: Int
    let activeDayCount: Int
    let maximumDailyValue: Int

    var id: UUID {
        taskID
    }

    var hasActivity: Bool {
        totalValue > 0
    }
}
