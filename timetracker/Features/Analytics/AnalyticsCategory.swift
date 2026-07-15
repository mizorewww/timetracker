import SwiftUI

enum AnalyticsCategory: String, CaseIterable, Identifiable {
    case overview
    case time
    case tasks
    case pomodoro
    case decisions
    case quality

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return AppStrings.localized("analytics.category.overview.title")
        case .time:
            return AppStrings.localized("analytics.category.time.title")
        case .tasks:
            return AppStrings.localized("analytics.category.tasks.title")
        case .pomodoro:
            return AppStrings.localized("analytics.category.pomodoro.title")
        case .decisions:
            return AppStrings.localized("analytics.category.decisions.title")
        case .quality:
            return AppStrings.localized("analytics.category.quality.title")
        }
    }

    var subtitle: String {
        switch self {
        case .overview:
            return AppStrings.localized("analytics.category.overview.subtitle")
        case .time:
            return AppStrings.localized("analytics.category.time.subtitle")
        case .tasks:
            return AppStrings.localized("analytics.category.tasks.subtitle")
        case .pomodoro:
            return AppStrings.localized("analytics.category.pomodoro.subtitle")
        case .decisions:
            return AppStrings.localized("analytics.category.decisions.subtitle")
        case .quality:
            return AppStrings.localized("analytics.category.quality.subtitle")
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            return "chart.bar.doc.horizontal"
        case .time:
            return "clock"
        case .tasks:
            return "chart.pie"
        case .pomodoro:
            return "timer"
        case .decisions:
            return "lightbulb"
        case .quality:
            return "waveform.path.ecg"
        }
    }

    var tint: Color {
        switch self {
        case .overview:
            return .blue
        case .time:
            return .cyan
        case .tasks:
            return .purple
        case .pomodoro:
            return .orange
        case .decisions:
            return .yellow
        case .quality:
            return .green
        }
    }

    func value(from snapshot: AnalyticsSnapshot) -> String {
        switch self {
        case .overview:
            return DurationFormatter.compact(snapshot.overview.grossSeconds)
        case .time:
            return DurationFormatter.compact(snapshot.overview.wallSeconds)
        case .tasks:
            return String(
                format: AppStrings.localized("analytics.category.value.tasksFormat"),
                snapshot.taskBreakdown.count
            )
        case .pomodoro:
            return String(
                format: AppStrings.localized("analytics.category.value.pomodorosFormat"),
                snapshot.overview.pomodoroCount
            )
        case .decisions:
            return String(
                format: AppStrings.localized("analytics.category.value.insightsFormat"),
                snapshot.insights.count
            )
        case .quality:
            return "\(Int((snapshot.quality.overlapRatio * 100).rounded()))%"
        }
    }

    func valueLabel(from snapshot: AnalyticsSnapshot) -> String {
        switch self {
        case .overview:
            return AppStrings.grossTime
        case .time:
            return AppStrings.wallTime
        case .tasks:
            return AppStrings.tasks
        case .pomodoro:
            return AppStrings.localized("analytics.metric.pomodoros")
        case .decisions:
            return AppStrings.localized("analytics.category.value.insights")
        case .quality:
            return AppStrings.localized("analytics.quality.overlapRatio")
        }
    }
}
