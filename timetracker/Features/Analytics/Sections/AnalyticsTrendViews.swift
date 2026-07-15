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
                    y: .value(AppStrings.wallTime, point.wallSeconds / 60)
                )
                .foregroundStyle(.blue)
                .accessibilityLabel(point.label)
                .accessibilityValue(
                    "\(AppStrings.wallTime), \(DurationFormatter.compact(point.wallSeconds))"
                )

                LineMark(
                    x: .value(AppStrings.localized("analytics.chart.day"), point.label),
                    y: .value(AppStrings.grossTime, point.grossSeconds / 60)
                )
                .foregroundStyle(.green)
                .symbol(.circle)
                .accessibilityLabel(point.label)
                .accessibilityValue(
                    "\(AppStrings.grossTime), \(DurationFormatter.compact(point.grossSeconds))"
                )
            }
            .chartYAxisLabel(AppStrings.localized("analytics.minutes"))
            .frame(height: 240)
            .accessibilityLabel(AppStrings.localized("analytics.dailyTrend.title"))
        }
    }
}
