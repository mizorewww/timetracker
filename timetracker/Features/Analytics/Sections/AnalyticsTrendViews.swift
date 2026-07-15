import Charts
import SwiftUI

struct DailyTrendContent: View {
    let daily: [DailyAnalyticsPoint]

    var body: some View {
        if daily.isEmpty || daily.allSatisfy({ $0.wallSeconds == 0 && $0.grossSeconds == 0 }) {
            EmptyStateRow(
                title: AppStrings.localized("analytics.empty.rangeTaskTime"),
                icon: "chart.xyaxis.line"
            )
        } else {
            Chart(daily) { point in
                BarMark(
                    x: .value(AppStrings.localized("analytics.chart.day"), point.label),
                    y: .value(AppStrings.wallTime, point.wallMinutes)
                )
                .foregroundStyle(
                    by: .value(
                        AppStrings.localized("analytics.chart.metric"),
                        AppStrings.wallTime
                    )
                )
                .accessibilityLabel(point.label)
                .accessibilityValue(
                    "\(AppStrings.wallTime), \(DurationFormatter.compact(point.wallSeconds))"
                )

                LineMark(
                    x: .value(AppStrings.localized("analytics.chart.day"), point.label),
                    y: .value(AppStrings.grossTime, point.grossMinutes)
                )
                .foregroundStyle(
                    by: .value(
                        AppStrings.localized("analytics.chart.metric"),
                        AppStrings.grossTime
                    )
                )
                .symbol(.circle)
                .accessibilityLabel(point.label)
                .accessibilityValue(
                    "\(AppStrings.grossTime), \(DurationFormatter.compact(point.grossSeconds))"
                )
            }
            .chartForegroundStyleScale([
                AppStrings.wallTime: Color.blue,
                AppStrings.grossTime: Color.green
            ])
            .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
            .chartYAxisLabel(AppStrings.localized("analytics.minutes"))
            .frame(height: 260)
            .accessibilityLabel(AppStrings.localized("analytics.dailyTrend.title"))
            .accessibilityIdentifier("analytics.dailyTrend.chart")
        }
    }
}
