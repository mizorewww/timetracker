import SwiftUI

struct TodayOverviewSection: View {
    let store: TimeTrackerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeOverviewHeader(
                container: .card,
                showsWallTime: store.preferences.showGrossAndWallTogether
            )
            MetricsPanel(store: store)
                .accessibilityIdentifier("home.overview")
        }
    }
}

struct HomeOverviewHeader: View {
    let container: HomeSectionContainer
    let showsWallTime: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            title
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("home.overview.header")
            HomeSectionInformationButton.overview(
                showsWallTime: showsWallTime
            )
        }
    }

    @ViewBuilder
    private var title: some View {
        switch container {
        case .card:
            Text(.app("home.overview.title"))
                .font(.headline)
        case .listSection:
            Text(.app("home.overview.title"))
        }
    }
}

struct MetricsPanel: View {
    let store: TimeTrackerStore

    var body: some View {
        MetricsPanelContent(store: store)
            .padding(14)
            .frame(maxWidth: .infinity)
            .appCard(padding: 0)
    }
}

private struct MetricsPanelContent: View {
    let store: TimeTrackerStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let metrics = metricItems(now: context.date)
            if dynamicTypeSize.isAccessibilitySize {
                verticalMetrics(metrics)
            } else {
                ViewThatFits(in: .horizontal) {
                    horizontalMetrics(metrics)
                    verticalMetrics(metrics)
                }
            }
        }
    }

    private func horizontalMetrics(_ metrics: [MetricSummaryItem]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(metrics) { metric in
                MetricCell(metric: metric, compact: false)
                if metric.id != metrics.last?.id {
                    Divider()
                }
            }
        }
    }

    private func verticalMetrics(_ metrics: [MetricSummaryItem]) -> some View {
        VStack(spacing: 12) {
            ForEach(metrics) { metric in
                MetricCell(metric: metric, compact: false)
                if metric.id != metrics.last?.id {
                    Divider()
                }
            }
        }
    }

    private func metricItems(now: Date) -> [MetricSummaryItem] {
        let snapshot = store.todayMetricsSnapshot(now: now)
        let grossTrend = trendDisplay(
            TodayMetricTrend(current: snapshot.grossSeconds, previous: snapshot.previousGrossSeconds)
        )
        let wallTrend = trendDisplay(
            TodayMetricTrend(current: snapshot.wallSeconds, previous: snapshot.previousWallSeconds)
        )

        let grossMetric = MetricSummaryItem(
            id: "gross",
            title: AppStrings.grossTime,
            value: DurationFormatter.compact(snapshot.grossSeconds),
            iconName: "square.stack.3d.up",
            tint: AppColors.grossTime,
            trendText: grossTrend.text,
            trendColor: grossTrend.color,
            alignment: .leading
        )
        guard store.preferences.showGrossAndWallTogether else {
            return [grossMetric]
        }
        return [
            grossMetric,
            MetricSummaryItem(
                id: "wall",
                title: AppStrings.wallTime,
                value: DurationFormatter.compact(snapshot.wallSeconds),
                iconName: "timeline.selection",
                tint: AppColors.wallTime,
                trendText: wallTrend.text,
                trendColor: wallTrend.color,
                alignment: .leading
            )
        ]
    }

    private func trendDisplay(_ trend: TodayMetricTrend) -> (text: String, color: Color) {
        switch trend {
        case .noComparison:
            return (AppStrings.localized("home.metric.noComparison"), .secondary)
        case let .increased(percent):
            return (String(format: AppStrings.localized("home.metric.upFromYesterday"), percent), .secondary)
        case let .decreased(percent):
            return (String(format: AppStrings.localized("home.metric.downFromYesterday"), percent), .secondary)
        case .unchanged:
            return (AppStrings.localized("home.metric.sameAsYesterday"), .secondary)
        }
    }
}
