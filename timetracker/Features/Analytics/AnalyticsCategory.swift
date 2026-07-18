import SwiftUI

enum AnalyticsCategory: String, CaseIterable, Hashable, Identifiable {
    case overview
    case time
    case tasks
    case pomodoro
    case decisions
    case quality

    static let questionCategories: [AnalyticsCategory] = [
        .overview,
        .time,
        .tasks,
        .pomodoro,
        .decisions,
        .quality
    ]

    var id: String { rawValue }

    var destinationTitle: String {
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

    var questionTitle: String {
        switch self {
        case .overview:
            return AppStrings.localized("analytics.question.overview")
        case .time:
            return AppStrings.localized("analytics.question.time")
        case .tasks:
            return AppStrings.localized("analytics.question.tasks")
        case .pomodoro:
            return AppStrings.localized("analytics.question.pomodoro")
        case .decisions:
            return AppStrings.localized("analytics.question.decisions")
        case .quality:
            return AppStrings.localized("analytics.question.quality")
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

    func answerPreview(from snapshot: AnalyticsSnapshot) -> String {
        guard snapshot.overview.grossSeconds > 0 ||
            (self == .pomodoro && snapshot.overview.pomodoroCount > 0) else {
            return AppStrings.localized("analytics.question.answer.noRecordedTime")
        }

        switch self {
        case .overview:
            return String(
                format: AppStrings.localized("analytics.question.answer.totalFormat"),
                DurationFormatter.compact(snapshot.overview.grossSeconds)
            )
        case .time:
            guard let peakHour = snapshot.rhythm.peakHour else {
                return AppStrings.localized("analytics.question.answer.noPeak")
            }
            return String(
                format: AppStrings.localized("analytics.question.answer.peakFormat"),
                peakHour,
                DurationFormatter.compact(snapshot.rhythm.peakHourSeconds)
            )
        case .tasks:
            guard let topTask = snapshot.taskBreakdown.first else {
                return AppStrings.localized("analytics.question.answer.noTask")
            }
            return String(
                format: AppStrings.localized("analytics.question.answer.taskFormat"),
                topTask.title,
                DurationFormatter.compact(topTask.grossSeconds)
            )
        case .pomodoro:
            let formatKey = snapshot.overview.pomodoroCount == 1
                ? "analytics.question.answer.focusSingularFormat"
                : "analytics.question.answer.focusFormat"
            return String(
                format: AppStrings.localized(formatKey),
                snapshot.overview.pomodoroCount
            )
        case .decisions:
            guard let insight = priorityInsight(from: snapshot.insights) else {
                return AppStrings.localized("analytics.question.answer.noSignal")
            }
            return String(
                format: AppStrings.localized("analytics.question.answer.signalFormat"),
                insight.title,
                insight.value
            )
        case .quality:
            return String(
                format: AppStrings.localized("analytics.question.answer.overlapFormat"),
                Int((snapshot.quality.overlapRatio * 100).rounded())
            )
        }
    }

    var openLabel: String {
        String(
            format: AppStrings.localized("analytics.question.openFormat"),
            destinationTitle
        )
    }

    private func priorityInsight(from insights: [AnalyticsInsight]) -> AnalyticsInsight? {
        if let warning = insights.first(where: {
            $0.severity == .warning || $0.severity == .critical
        }) {
            return warning
        }
        return insights.first(where: { $0.id == "comparison" }) ?? insights.first
    }
}
