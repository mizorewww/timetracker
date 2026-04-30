import SwiftUI

struct MetricsAndActions: View {
    @ObservedObject var store: TimeTrackerStore
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

struct MetricsPanel: View {
    @ObservedObject var store: TimeTrackerStore
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
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompactPhone: Bool {
        SizeClassLayoutPolicy(horizontalSizeClass: horizontalSizeClass).isCompactPhone
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let metrics = metricItems(now: context.date)
            if isCompactPhone {
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

        return [
            MetricSummaryItem(
                id: "tracked",
                title: AppStrings.todayTracked,
                value: DurationFormatter.compact(todayGross),
                iconName: "clock.badge.checkmark",
                tint: .blue,
                trendText: grossTrend.text,
                trendColor: grossTrend.color,
                alignment: .leading
            ),
            MetricSummaryItem(
                id: "wall",
                title: AppStrings.wallTime,
                value: DurationFormatter.compact(todayWall),
                iconName: "timeline.selection",
                tint: .green,
                trendText: wallTrend.text,
                trendColor: wallTrend.color,
                alignment: .center
            ),
            MetricSummaryItem(
                id: "gross",
                title: AppStrings.grossTime,
                value: DurationFormatter.compact(todayGross),
                iconName: "square.stack.3d.up",
                tint: .orange,
                trendText: grossTrend.text,
                trendColor: grossTrend.color,
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

struct MetricSummaryItem: Identifiable {
    let id: String
    let title: String
    let value: String
    let iconName: String
    let tint: Color
    let trendText: String
    let trendColor: Color
    let alignment: MetricTextAlignment
}

enum MetricTextAlignment {
    case leading
    case center
    case trailing

    var frameAlignment: Alignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

struct MetricCell: View {
    let metric: MetricSummaryItem
    var compact: Bool = false

    var body: some View {
        VStack(alignment: metric.alignment.horizontalAlignment, spacing: compact ? 4 : 6) {
            HStack(spacing: 5) {
                Image(systemName: metric.iconName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(metric.tint)
                Text(metric.title)
                    .font((compact ? Font.caption2 : Font.caption).weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, alignment: metric.alignment.frameAlignment)

            Text(metric.value)
                .font(.system(size: compact ? 20 : 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: metric.alignment.frameAlignment)

            Text(metric.trendText)
                .font(.caption2)
                .foregroundStyle(metric.trendColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: metric.alignment.frameAlignment)
        }
        .frame(maxWidth: .infinity, alignment: metric.alignment.frameAlignment)
        .padding(.horizontal, compact ? 4 : 10)
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
