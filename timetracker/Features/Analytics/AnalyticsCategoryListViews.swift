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
            return String(format: AppStrings.localized("analytics.category.value.tasksFormat"), snapshot.taskBreakdown.count)
        case .pomodoro:
            return String(format: AppStrings.localized("analytics.category.value.pomodorosFormat"), snapshot.overview.pomodoroCount)
        case .decisions:
            return String(format: AppStrings.localized("analytics.category.value.insightsFormat"), snapshot.insights.count)
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

struct AnalyticsHomeSummaryRow: View {
    let snapshot: AnalyticsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(DurationFormatter.compact(snapshot.overview.grossSeconds))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(AppStrings.grossTime)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(DurationFormatter.compact(snapshot.overview.wallSeconds))
                        .font(.title3.weight(.semibold).monospacedDigit())
                    Text(AppStrings.wallTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 14) {
                Label("\(snapshot.overview.pomodoroCount)", systemImage: "timer")
                Label(DurationFormatter.compact(snapshot.rhythm.dailyAverageGrossSeconds), systemImage: "calendar")
                Label("\(Int((snapshot.quality.overlapRatio * 100).rounded()))%", systemImage: "rectangle.2.swap")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("analytics.homeSummary")
    }
}

struct AnalyticsCategoryRow: View {
    let category: AnalyticsCategory
    let snapshot: AnalyticsSnapshot

    var body: some View {
        HStack(spacing: 12) {
            SettingsRowIcon(systemImage: category.systemImage, tint: category.tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(category.title)
                    .font(.body)
                Text(category.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(category.value(from: snapshot))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Text(category.valueLabel(from: snapshot))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("analytics.category.\(category.rawValue)")
    }
}
