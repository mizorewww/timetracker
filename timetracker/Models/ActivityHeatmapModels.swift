import Foundation

nonisolated enum ActivityHeatmapIntensity: Int, CaseIterable, Equatable, Sendable {
    case none
    case low
    case medium
    case high
    case maximum

    init(completionCount: Int) {
        self = switch max(0, completionCount) {
        case 0: .none
        case 1: .low
        case 2: .medium
        case 3: .high
        default: .maximum
        }
    }
}

nonisolated struct ActivityHeatmapDay: Identifiable, Equatable, Sendable {
    let date: Date
    let completionCount: Int
    let intensity: ActivityHeatmapIntensity
    let isFuture: Bool
    let isToday: Bool

    var id: Date { date }
}

nonisolated struct ActivityHeatmapWeek: Identifiable, Equatable, Sendable {
    let startDate: Date
    let days: [ActivityHeatmapDay]

    var id: Date { startDate }
}

nonisolated struct ActivityHeatmapSnapshot: Equatable, Sendable {
    let interval: DateInterval
    let today: Date
    let weeks: [ActivityHeatmapWeek]
    let totalCompletionCount: Int
    let activeDayCount: Int

    var hasActivity: Bool {
        totalCompletionCount > 0
    }
}
