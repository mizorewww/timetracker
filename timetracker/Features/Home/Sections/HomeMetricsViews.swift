import SwiftUI

struct MetricsAndActions: View {
    let store: TimeTrackerStore
    let horizontal: Bool

    var body: some View {
        Group {
            if horizontal {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 14) {
                        MetricsPanelContent(store: store)
                            .frame(maxWidth: .infinity)

                        Divider()
                            .frame(height: 64)

                        ActionStack(store: store, buttonHeight: 36, spacing: 8)
                            .frame(width: 190)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .appCard(padding: 0)

                    VStack(spacing: 16) {
                        MetricsPanel(store: store)
                        ActionStack(store: store, buttonHeight: 40)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    MetricsPanel(store: store)
                    ActionStack(store: store, buttonHeight: 44, spacing: 10)
                }
            }
        }
    }
}

var phoneToolbarPlacement: ToolbarItemPlacement {
    #if os(iOS)
    return .topBarTrailing
    #else
    return .automatic
    #endif
}

var phoneLeadingToolbarPlacement: ToolbarItemPlacement {
    #if os(iOS)
    return .topBarLeading
    #else
    return .automatic
    #endif
}

struct MetricsPanel: View {
    let store: TimeTrackerStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompactPhone: Bool {
        SizeClassLayoutPolicy(horizontalSizeClass: horizontalSizeClass).isCompactPhone
    }

    var body: some View {
        MetricsPanelContent(store: store)
            .padding(isCompactPhone ? 12 : 14)
            .frame(maxWidth: .infinity)
            .appCard(padding: 0)
    }
}

private struct MetricsPanelContent: View {
    let store: TimeTrackerStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isCompactPhone: Bool {
        SizeClassLayoutPolicy(horizontalSizeClass: horizontalSizeClass).isCompactPhone
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let metrics = metricItems(now: context.date)
            if isCompactPhone && !dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(metrics) { metric in
                        MetricCell(metric: metric, compact: true)
                    }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) {
                        ForEach(metrics) { metric in
                            MetricCell(metric: metric, compact: false)
                            if metric.id != metrics.last?.id {
                                Divider()
                            }
                        }
                    }

                    VStack(spacing: 12) {
                        ForEach(metrics) { metric in
                            MetricCell(metric: metric, compact: false)
                            if metric.id != metrics.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private func metricItems(now: Date) -> [MetricSummaryItem] {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let todayGross = store.todayGrossSeconds(now: now)
        let todayWall = store.todayWallSeconds(now: now)
        let yesterdayGross = store.daySeconds(for: yesterday, mode: .gross, now: now)
        let yesterdayWall = store.daySeconds(for: yesterday, mode: .wallClock, now: now)
        let grossTrend = trend(current: todayGross, previous: yesterdayGross)
        let wallTrend = trend(current: todayWall, previous: yesterdayWall)

        let grossMetric = MetricSummaryItem(
            id: "gross",
            title: AppStrings.grossTime,
            value: DurationFormatter.compact(todayGross),
            iconName: "square.stack.3d.up",
            tint: .blue,
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
                value: DurationFormatter.compact(todayWall),
                iconName: "timeline.selection",
                tint: .green,
                trendText: wallTrend.text,
                trendColor: wallTrend.color,
                alignment: .trailing
            )
        ]
    }

    private func trend(current: Int, previous: Int) -> (text: String, color: Color) {
        guard previous > 0 else {
            return (AppStrings.localized("home.metric.noComparison"), .secondary)
        }
        let percent = Int(round((Double(current - previous) / Double(previous)) * 100))
        if percent > 0 {
            return (String(format: AppStrings.localized("home.metric.upFromYesterday"), percent), .green)
        }
        if percent < 0 {
            return (String(format: AppStrings.localized("home.metric.downFromYesterday"), abs(percent)), .red)
        }
        return (AppStrings.localized("home.metric.sameAsYesterday"), .secondary)
    }
}

struct MiniBars: View {
    let values: [Int]
    let tint: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tint)
                    .frame(width: 4, height: CGFloat(max(3, value * 2)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
