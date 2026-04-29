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
                analyticsContent(snapshot: snapshot, now: now)
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

    private func analyticsContent(snapshot: AnalyticsSnapshot, now: Date) -> some View {
        let overview = snapshot.overview
        let daily = snapshot.daily
        let tasks = snapshot.taskBreakdown
        let overlaps = snapshot.overlaps
        let todaySegments = store.todaySegments

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        if horizontalSizeClass != .compact {
                            analyticsTitle(range)
                        }
                        Spacer()
                        analyticsRangePicker
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        if horizontalSizeClass != .compact {
                            analyticsTitle(range)
                        }
                        analyticsRangePicker
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                    AnalyticsMetric(title: AppStrings.wallTime, value: DurationFormatter.compact(overview.wallSeconds), footnote: AppStrings.localized("analytics.wall.footnote"))
                    AnalyticsMetric(title: AppStrings.grossTime, value: DurationFormatter.compact(overview.grossSeconds), footnote: AppStrings.localized("analytics.gross.footnote"))
                    AnalyticsMetric(title: AppStrings.localized("analytics.metric.overlap"), value: DurationFormatter.compact(overview.overlapSeconds), footnote: AppStrings.localized("analytics.overlap.footnote"))
                    AnalyticsMetric(title: AppStrings.localized("analytics.metric.pomodoros"), value: "\(overview.pomodoroCount)", footnote: AppStrings.localized("analytics.pomodoros.footnote"))
                }

                TaskForecastsCard(store: store)

                if range == .today {
                    TodayActivityCard(store: store, segments: todaySegments, now: now)
                    OverlappingTimelineCard(store: store, segments: todaySegments, now: now)
                    TaskDonutCard(tasks: tasks, totalSeconds: max(overview.grossSeconds, 1))
                } else {
                    AnalyticsChartCard(title: AppStrings.localized("analytics.dailyTrend.title"), subtitle: AppStrings.localized("analytics.dailyTrend.subtitle")) {
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

                AnalyticsChartCard(title: AppStrings.localized("analytics.overlap.title"), subtitle: AppStrings.localized("analytics.overlap.subtitle")) {
                    VStack(spacing: 0) {
                        if overlaps.isEmpty {
                            EmptyStateRow(title: AppStrings.localized("analytics.empty.overlap"), icon: "rectangle.2.swap")
                        } else {
                            ForEach(overlaps.prefix(6)) { overlap in
                                OverlapRow(overlap: overlap)
                                if overlap.id != overlaps.prefix(6).last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func analyticsTitle(_ range: AnalyticsRange) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppStrings.analytics)
                .font(.largeTitle.bold())
            Text(range == .today ? AppStrings.localized("analytics.header.today") : AppStrings.localized("analytics.header.other"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var analyticsRangePicker: some View {
        Picker(AppStrings.localized("analytics.range"), selection: $range) {
            ForEach(AnalyticsRange.allCases) { range in
                Text(range.displayName).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 280)
    }
}

struct AnalyticsMetric: View {
    let title: String
    let value: String
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }
}

struct AnalyticsChartCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .appCard()
    }
}
