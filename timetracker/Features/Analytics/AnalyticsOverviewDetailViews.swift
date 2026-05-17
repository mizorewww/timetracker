import SwiftUI

struct AnalyticsMetricList: View {
    let overview: AnalyticsOverview
    let comparison: AnalyticsComparison
    let rhythm: AnalyticsRhythm

    var body: some View {
        VStack(spacing: 0) {
            AnalyticsMetricListRow(
                title: AppStrings.wallTime,
                value: DurationFormatter.compact(overview.wallSeconds),
                footnote: String(format: AppStrings.localized("analytics.metric.deltaFootnoteFormat"), deltaText(comparison.wallDeltaSeconds)),
                systemImage: "clock",
                tint: .blue
            )
            Divider()
            AnalyticsMetricListRow(
                title: AppStrings.grossTime,
                value: DurationFormatter.compact(overview.grossSeconds),
                footnote: String(format: AppStrings.localized("analytics.metric.deltaFootnoteFormat"), deltaText(comparison.grossDeltaSeconds)),
                systemImage: "sum",
                tint: .green
            )
            Divider()
            AnalyticsMetricListRow(
                title: AppStrings.localized("analytics.metric.overlap"),
                value: DurationFormatter.compact(overview.overlapSeconds),
                footnote: AppStrings.localized("analytics.overlap.footnote"),
                systemImage: "rectangle.2.swap",
                tint: .orange
            )
            Divider()
            AnalyticsMetricListRow(
                title: AppStrings.localized("analytics.metric.pomodoros"),
                value: "\(overview.pomodoroCount)",
                footnote: AppStrings.localized("analytics.pomodoros.footnote"),
                systemImage: "timer",
                tint: .red
            )
            Divider()
            AnalyticsMetricListRow(
                title: AppStrings.localized("analytics.metric.dailyPace"),
                value: DurationFormatter.compact(rhythm.dailyAverageGrossSeconds),
                footnote: String(format: AppStrings.localized("analytics.metric.activeDaysFormat"), rhythm.activeDayCount),
                systemImage: "calendar",
                tint: .purple
            )
        }
    }

    private func deltaText(_ seconds: Int) -> String {
        if seconds == 0 {
            return DurationFormatter.compact(0)
        }
        let prefix = seconds > 0 ? "+" : "-"
        return "\(prefix)\(DurationFormatter.compact(abs(seconds)))"
    }
}

private struct AnalyticsMetricListRow: View {
    let title: String
    let value: String
    let footnote: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            SettingsRowIcon(systemImage: systemImage, tint: tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.vertical, 10)
    }
}

struct AnalyticsGlossaryList: View {
    var body: some View {
        VStack(spacing: 0) {
            AnalyticsGlossaryRow(title: AppStrings.grossTime, bodyText: AppStrings.localized("analytics.glossary.gross"))
            Divider()
            AnalyticsGlossaryRow(title: AppStrings.wallTime, bodyText: AppStrings.localized("analytics.glossary.wall"))
            Divider()
            AnalyticsGlossaryRow(title: AppStrings.localized("analytics.metric.overlap"), bodyText: AppStrings.localized("analytics.glossary.overlap"))
        }
    }
}

private struct AnalyticsGlossaryRow: View {
    let title: String
    let bodyText: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(bodyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }
}
