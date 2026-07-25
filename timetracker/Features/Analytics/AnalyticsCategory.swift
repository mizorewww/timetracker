import SwiftUI

enum AnalyticsCategory: String, CaseIterable, Hashable, Identifiable {
    case overview
    case time
    case tasks
    case pomodoro
    case decisions
    case quality

    static let reviewCategories: [AnalyticsCategory] = [.decisions, .quality]
    static let exploreCategories: [AnalyticsCategory] = [
        .time,
        .tasks,
        .pomodoro,
        .overview,
    ]

    var id: String {
        rawValue
    }

    var destinationTitle: String {
        switch self {
        case .overview:
            AppStrings.localized("analytics.category.overview.title")
        case .time:
            AppStrings.localized("analytics.category.time.title")
        case .tasks:
            AppStrings.localized("analytics.category.tasks.title")
        case .pomodoro:
            AppStrings.localized("analytics.category.pomodoro.title")
        case .decisions:
            AppStrings.localized("analytics.category.decisions.title")
        case .quality:
            AppStrings.localized("analytics.category.quality.title")
        }
    }

    var questionTitle: String {
        switch self {
        case .overview:
            AppStrings.localized("analytics.question.overview")
        case .time:
            AppStrings.localized("analytics.question.time")
        case .tasks:
            AppStrings.localized("analytics.question.tasks")
        case .pomodoro:
            AppStrings.localized("analytics.question.pomodoro")
        case .decisions:
            AppStrings.localized("analytics.question.decisions")
        case .quality:
            AppStrings.localized("analytics.question.quality")
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            "chart.bar.doc.horizontal"
        case .time:
            "clock"
        case .tasks:
            "chart.pie"
        case .pomodoro:
            "timer"
        case .decisions:
            "lightbulb"
        case .quality:
            "waveform.path.ecg"
        }
    }

    var tint: Color {
        switch self {
        case .overview:
            .blue
        case .time:
            .cyan
        case .tasks:
            .purple
        case .pomodoro:
            .orange
        case .decisions:
            .yellow
        case .quality:
            .green
        }
    }

    func answerPreview(from snapshot: AnalyticsSnapshot) -> String {
        guard snapshot.overview.grossSeconds > 0 ||
            (self == .pomodoro && snapshot.overview.pomodoroCount > 0)
        else {
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
                format: AppStrings.localized(
                    "analytics.question.answer.taskCategoryFormat"
                ),
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
