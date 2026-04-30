import Charts
import Combine
import SwiftUI

struct AnalyticsView: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var range: AnalyticsRange = .today
    @State private var now = Date()
    private let analyticsRefreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let snapshot = store.cachedAnalyticsSnapshot(for: range) {
                AnalyticsContent(
                    store: store,
                    snapshot: snapshot,
                    range: $range,
                    now: now,
                    horizontalSizeClass: horizontalSizeClass
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(AppStrings.analytics)
        .background(AppColors.background)
        .task(id: range) {
            store.refreshAnalyticsSnapshot(for: range, now: now)
        }
        .onReceive(analyticsRefreshTimer) { date in
            now = date
            store.refreshAnalyticsSnapshot(for: range, now: date)
        }
    }
}

private struct AnalyticsContent: View {
    @ObservedObject var store: TimeTrackerStore
    let snapshot: AnalyticsSnapshot
    @Binding var range: AnalyticsRange
    let now: Date
    let horizontalSizeClass: UserInterfaceSizeClass?

    private var layout: AnalyticsLayoutPolicy {
        AnalyticsLayoutPolicy(horizontalSizeClass: horizontalSizeClass)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AnalyticsHeader(range: $range, layout: layout)
                AnalyticsMetricGrid(overview: snapshot.overview)
                TaskForecastsCard(store: store)
                AnalyticsRangeSection(store: store, snapshot: snapshot, range: range, now: now)
                AnalyticsOverlapCard(overlaps: snapshot.overlaps)
            }
            .padding()
        }
    }
}

private struct AnalyticsHeader: View {
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

private struct AnalyticsMetricGrid: View {
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

private struct AnalyticsRangeSection: View {
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

private struct DailyTrendCard: View {
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

private struct AnalyticsOverlapCard: View {
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
