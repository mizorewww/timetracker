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
            DailyTimeSeriesChart(
                points: daily,
                mode: .wallBarsAndGrossLine,
                accessibilityTitle: AppStrings.localized("analytics.dailyTrend.title")
            )
            .frame(height: 260)
            .accessibilityIdentifier("analytics.dailyTrend.chart")
        }
    }
}
