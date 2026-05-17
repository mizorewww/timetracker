import Charts
import SwiftUI

struct AnalyticsHeader: View {
    @Binding var range: AnalyticsRange
    @Binding var referenceDate: Date
    let now: Date
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
            controls
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            if layout.showsPageTitleInContent {
                title
            }
            controls
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppStrings.analytics)
                .font(.largeTitle.bold())
            Text(headerSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            AnalyticsPeriodTitle(range: range, referenceDate: referenceDate)
        }
    }

    private var headerSubtitle: String {
        range == .today
            ? AppStrings.localized("analytics.header.today")
            : AppStrings.localized("analytics.header.other")
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                rangePicker
                AnalyticsPeriodControl(range: range, referenceDate: $referenceDate, liveNow: now)
            }

            VStack(alignment: .leading, spacing: 8) {
                rangePicker
                AnalyticsPeriodControl(range: range, referenceDate: $referenceDate, liveNow: now)
            }
        }
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

struct AnalyticsPeriodTitle: View {
    let range: AnalyticsRange
    let referenceDate: Date

    var body: some View {
        Label {
            Text(AnalyticsPeriodText.title(for: range, date: referenceDate))
                .lineLimit(1)
        } icon: {
            Image(systemName: "calendar")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.10), in: Capsule())
        .accessibilityIdentifier("analytics.periodTitle")
    }
}

struct AnalyticsMetricGrid: View {
    let overview: AnalyticsOverview
    let comparison: AnalyticsComparison
    let rhythm: AnalyticsRhythm

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            AnalyticsMetric(
                title: AppStrings.wallTime,
                value: DurationFormatter.compact(overview.wallSeconds),
                footnote: String(format: AppStrings.localized("analytics.metric.deltaFootnoteFormat"), deltaText(comparison.wallDeltaSeconds))
            )
            AnalyticsMetric(
                title: AppStrings.grossTime,
                value: DurationFormatter.compact(overview.grossSeconds),
                footnote: String(format: AppStrings.localized("analytics.metric.deltaFootnoteFormat"), deltaText(comparison.grossDeltaSeconds))
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
            AnalyticsMetric(
                title: AppStrings.localized("analytics.metric.dailyPace"),
                value: DurationFormatter.compact(rhythm.dailyAverageGrossSeconds),
                footnote: String(format: AppStrings.localized("analytics.metric.activeDaysFormat"), rhythm.activeDayCount)
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

struct AnalyticsMetricGlossaryStrip: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                glossaryItem(title: AppStrings.grossTime, body: AppStrings.localized("analytics.glossary.gross"))
                glossaryItem(title: AppStrings.wallTime, body: AppStrings.localized("analytics.glossary.wall"))
                glossaryItem(title: AppStrings.localized("analytics.metric.overlap"), body: AppStrings.localized("analytics.glossary.overlap"))
            }

            VStack(alignment: .leading, spacing: 8) {
                glossaryItem(title: AppStrings.grossTime, body: AppStrings.localized("analytics.glossary.gross"))
                glossaryItem(title: AppStrings.wallTime, body: AppStrings.localized("analytics.glossary.wall"))
                glossaryItem(title: AppStrings.localized("analytics.metric.overlap"), body: AppStrings.localized("analytics.glossary.overlap"))
            }
        }
        .appCard(padding: 12)
    }

    private func glossaryItem(title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(title): \(body)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AnalyticsRangeSection: View {
    let snapshot: AnalyticsSnapshot
    let range: AnalyticsRange

    var body: some View {
        if range == .today {
            TodayActivityCard(activity: snapshot.todayActivity)
            OverlappingTimelineCard(timeline: snapshot.timeline)
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
            DailyTrendContent(daily: daily)
        }
    }
}

struct DailyTrendContent: View {
    let daily: [DailyAnalyticsPoint]

    var body: some View {
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

struct AnalyticsOverlapCard: View {
    let overlaps: [OverlapAnalyticsPoint]

    var body: some View {
        AnalyticsChartCard(
            title: AppStrings.localized("analytics.overlap.title"),
            subtitle: AppStrings.localized("analytics.overlap.subtitle")
        ) {
            AnalyticsOverlapContent(overlaps: overlaps)
        }
    }
}

struct AnalyticsOverlapContent: View {
    let overlaps: [OverlapAnalyticsPoint]

    var body: some View {
        VStack(spacing: 0) {
            if overlaps.isEmpty {
                EmptyStateRow(
                    title: AppStrings.localized("analytics.empty.overlap"),
                    icon: "rectangle.2.swap"
                )
            } else {
                ForEach(overlaps.prefix(6).enumerated(), id: \.element.id) { index, overlap in
                    OverlapRow(overlap: overlap)
                    if index < min(overlaps.count, 6) - 1 {
                        Divider()
                    }
                }
            }
        }
    }
}
