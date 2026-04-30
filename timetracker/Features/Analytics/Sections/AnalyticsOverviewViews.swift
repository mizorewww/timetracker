import Charts
import SwiftUI

struct AnalyticsHeader: View {
    @Binding var range: AnalyticsRange
    let layout: AnalyticsLayoutPolicy

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalLayout
            compactLayout
        }
    }

    private var horizontalLayout: some View {
        HStack {
            if layout.showsPageTitleInContent {
                title
            }
            Spacer()
            rangePicker
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            if layout.showsPageTitleInContent {
                title
            }
            rangePicker
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppStrings.analytics)
                .font(.largeTitle.bold())
            Text(headerSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var headerSubtitle: String {
        range == .today
            ? AppStrings.localized("analytics.header.today")
            : AppStrings.localized("analytics.header.other")
    }

    private var rangePicker: some View {
        Picker(AppStrings.localized("analytics.range"), selection: $range) {
            ForEach(AnalyticsRange.allCases) { range in
                Text(range.displayName).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 280)
    }
}

struct AnalyticsMetricGrid: View {
    let overview: AnalyticsOverview

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            AnalyticsMetric(
                title: AppStrings.wallTime,
                value: DurationFormatter.compact(overview.wallSeconds),
                footnote: AppStrings.localized("analytics.wall.footnote")
            )
            AnalyticsMetric(
                title: AppStrings.grossTime,
                value: DurationFormatter.compact(overview.grossSeconds),
                footnote: AppStrings.localized("analytics.gross.footnote")
            )
            AnalyticsMetric(
                title: AppStrings.localized("analytics.metric.overlap"),
                value: DurationFormatter.compact(overview.overlapSeconds),
                footnote: AppStrings.localized("analytics.overlap.footnote")
            )
            AnalyticsMetric(
                title: AppStrings.localized("analytics.metric.pomodoros"),
                value: "\(overview.pomodoroCount)",
                footnote: AppStrings.localized("analytics.pomodoros.footnote")
            )
        }
    }
}

struct AnalyticsRangeSection: View {
    @ObservedObject var store: TimeTrackerStore
    let snapshot: AnalyticsSnapshot
    let range: AnalyticsRange
    let now: Date

    private var todaySegments: [TimeSegment] {
        store.todaySegments
    }

    var body: some View {
        if range == .today {
            TodayActivityCard(store: store, segments: todaySegments, now: now)
            OverlappingTimelineCard(store: store, segments: todaySegments, now: now)
            TaskDonutCard(
                tasks: snapshot.taskBreakdown,
                totalSeconds: max(snapshot.overview.grossSeconds, 1)
            )
        } else {
            DailyTrendCard(daily: snapshot.daily)
        }
    }
}

struct DailyTrendCard: View {
    let daily: [DailyAnalyticsPoint]

    var body: some View {
        AnalyticsChartCard(
            title: AppStrings.localized("analytics.dailyTrend.title"),
            subtitle: AppStrings.localized("analytics.dailyTrend.subtitle")
        ) {
            Chart(daily) { point in
                BarMark(
                    x: .value("Day", point.label),
                    y: .value("Wall Minutes", point.wallSeconds / 60)
                )
                .foregroundStyle(.blue)

                LineMark(
                    x: .value("Day", point.label),
                    y: .value("Gross Minutes", point.grossSeconds / 60)
                )
                .foregroundStyle(.green)
                .symbol(.circle)
            }
            .chartYAxisLabel(AppStrings.localized("analytics.minutes"))
            .frame(height: 240)
        }
    }
}

struct AnalyticsOverlapCard: View {
    let overlaps: [OverlapAnalyticsPoint]

    var body: some View {
        AnalyticsChartCard(
            title: AppStrings.localized("analytics.overlap.title"),
            subtitle: AppStrings.localized("analytics.overlap.subtitle")
        ) {
            VStack(spacing: 0) {
                if overlaps.isEmpty {
                    EmptyStateRow(
                        title: AppStrings.localized("analytics.empty.overlap"),
                        icon: "rectangle.2.swap"
                    )
                } else {
                    ForEach(Array(overlaps.prefix(6).enumerated()), id: \.element.id) { index, overlap in
                        OverlapRow(overlap: overlap)
                        if index < min(overlaps.count, 6) - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}
