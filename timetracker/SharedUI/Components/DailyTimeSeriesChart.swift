import Charts
import SwiftUI

enum DailyTimeSeriesChartMode {
    case grossBars
    case wallBarsAndGrossLine
}

nonisolated enum DailyTimeSeriesXAxisPolicy {
    static func labelIndices(
        pointCount: Int,
        maximumLabelCount: Int
    ) -> [Int] {
        guard pointCount > 0, maximumLabelCount > 0 else { return [] }
        let labelCount = min(pointCount, maximumLabelCount)
        guard labelCount > 1 else { return [0] }

        return (0 ..< labelCount).map { position in
            position * (pointCount - 1) / (labelCount - 1)
        }
    }
}

struct DailyTimeSeriesChart: View {
    let points: [DailyAnalyticsPoint]
    let mode: DailyTimeSeriesChartMode
    let accessibilityTitle: String
    var accessibilitySummary: String?
    var dateDomain: ClosedRange<Date>?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.locale) private var locale

    var body: some View {
        switch mode {
        case .grossBars:
            grossChart
        case .wallBarsAndGrossLine:
            comparisonChart
        }
    }

    private var grossChart: some View {
        configuredChart
            .chartLegend(.hidden)
            .chartXScale(
                domain: resolvedDateDomain,
                range: .plotDimension(
                    startPadding: 8,
                    endPadding: trailingAxisClearance
                )
            )
            .accessibilityLabel(accessibilityTitle)
            .accessibilityValue(
                accessibilitySummary ??
                    DurationFormatter.spoken(
                        points.reduce(0) { $0 + $1.grossSeconds },
                        locale: locale
                    )
            )
    }

    private var comparisonChart: some View {
        configuredChart
            .chartForegroundStyleScale([
                AppStrings.wallTime: AppColors.wallTime,
                AppStrings.grossTime: AppColors.grossTime,
            ])
            .chartLegend(
                position: .bottom,
                alignment: .leading,
                spacing: 12
            )
    }

    private var configuredChart: some View {
        chart
            .chartYAxis {
                AxisMarks(
                    position: .trailing,
                    values: .automatic(desiredCount: 3)
                ) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) {
                            Text(
                                DurationFormatter.chartAxis(
                                    Int((minutes * 60).rounded()),
                                    locale: locale
                                )
                            )
                        }
                    }
                }
            }
            .chartXAxis {
                if mode == .grossBars {
                    AxisMarks(values: .stride(by: .day)) {
                        AxisValueLabel(
                            format: .dateTime.weekday(.abbreviated)
                        )
                    }
                } else {
                    AxisMarks(values: comparisonXAxisDates) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(comparisonXAxisLabel(for: date))
                            }
                        }
                    }
                }
            }
            .chartYScale(domain: .automatic(includesZero: true))
    }

    private var chart: some View {
        Chart(points) { point in
            if mode == .grossBars {
                BarMark(
                    x: .value(
                        AppStrings.localized("analytics.chart.day"),
                        point.date,
                        unit: .day
                    ),
                    y: .value(AppStrings.grossTime, point.grossMinutes),
                    width: .ratio(0.62)
                )
                .foregroundStyle(AppColors.grossTime)
                .cornerRadius(3)
                .accessibilityLabel(accessibleDate(point.date))
                .accessibilityValue(
                    "\(AppStrings.grossTime), \(DurationFormatter.spoken(point.grossSeconds, locale: locale))"
                )
            } else {
                BarMark(
                    x: .value(
                        AppStrings.localized("analytics.chart.day"),
                        point.date,
                        unit: .day
                    ),
                    y: .value(AppStrings.wallTime, point.wallMinutes),
                    width: .ratio(0.62)
                )
                .foregroundStyle(
                    by: .value(
                        AppStrings.localized("analytics.chart.metric"),
                        AppStrings.wallTime
                    )
                )
                .accessibilityLabel(accessibleDate(point.date))
                .accessibilityValue(
                    "\(AppStrings.wallTime), \(DurationFormatter.spoken(point.wallSeconds, locale: locale))"
                )

                LineMark(
                    x: .value(
                        AppStrings.localized("analytics.chart.day"),
                        point.date,
                        unit: .day
                    ),
                    y: .value(AppStrings.grossTime, point.grossMinutes)
                )
                .foregroundStyle(
                    by: .value(
                        AppStrings.localized("analytics.chart.metric"),
                        AppStrings.grossTime
                    )
                )
                .symbol(.circle)
                .accessibilityLabel(accessibleDate(point.date))
                .accessibilityValue(
                    "\(AppStrings.grossTime), \(DurationFormatter.spoken(point.grossSeconds, locale: locale))"
                )
            }
        }
    }

    private func accessibleDate(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .weekday(.wide)
                .month(.wide)
                .day()
                .locale(locale)
        )
    }

    private var resolvedDateDomain: ClosedRange<Date> {
        if let dateDomain {
            return dateDomain
        }
        let start = points.first?.date ?? .distantPast
        let end = points.last?.date ?? start
        return start ... max(start.addingTimeInterval(1), end)
    }

    private var trailingAxisClearance: CGFloat {
        horizontalSizeClass == .compact ? 8 : 48
    }

    private var comparisonXAxisDates: [Date] {
        DailyTimeSeriesXAxisPolicy.labelIndices(
            pointCount: points.count,
            maximumLabelCount: horizontalSizeClass == .compact ? 5 : 8
        )
        .map { points[$0].date }
    }

    private func comparisonXAxisLabel(for date: Date) -> String {
        points.first(where: { $0.date == date })?.label ?? date.formatted(
            .dateTime.day().locale(locale)
        )
    }
}
