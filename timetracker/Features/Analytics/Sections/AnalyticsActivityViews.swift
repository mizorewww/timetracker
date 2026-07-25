import SwiftUI

struct TodayActivityContent: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 150
    let activity: [HourTaskActivity]

    private var totalSeconds: Int {
        activity.reduce(0) { $0 + $1.totalSeconds }
    }

    private var legendItems: [HourTaskSlice] {
        let grouped = Dictionary(grouping: activity.flatMap(\.slices), by: \.taskID)
        return grouped.compactMap { _, slices -> HourTaskSlice? in
            guard let first = slices.first else { return nil }
            return HourTaskSlice(
                taskID: first.taskID,
                title: first.title,
                symbolName: first.symbolName,
                colorHex: first.colorHex,
                seconds: slices.reduce(0) { $0 + $1.seconds }
            )
        }
        .sorted { lhs, rhs in
            if lhs.seconds == rhs.seconds {
                return lhs.taskID.uuidString < rhs.taskID.uuidString
            }
            return lhs.seconds > rhs.seconds
        }
        .prefix(6)
        .map { $0 }
    }

    private var hourScale: HourActivityScale {
        HourActivityScale(hourTotals: activity.map(\.totalSeconds))
    }

    private var hourMarkers: [Int] {
        dynamicTypeSize.isAccessibilitySize ? [0, 12, 24] : [0, 6, 12, 18, 24]
    }

    private var legendColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            [GridItem(.flexible(), alignment: .leading)]
        } else {
            [GridItem(.adaptive(minimum: 130), alignment: .leading)]
        }
    }

    var body: some View {
        if totalSeconds == 0 {
            EmptyStateRow(title: AppStrings.localized("analytics.empty.todayTaskTime"), icon: "chart.bar")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                TodayActivityHeader(totalSeconds: totalSeconds)

                activityBars

                hourAxis

                LazyVGrid(columns: legendColumns, alignment: .leading, spacing: 8) {
                    ForEach(legendItems) { item in
                        AnalyticsLegendSwatch(color: item.color, title: item.title)
                    }
                }
            }
            .accessibilityIdentifier("analytics.hourDistribution.content")
        }
    }

    private var activityBars: some View {
        let scale = hourScale

        return GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(activity) { point in
                    HourTaskActivityBar(
                        point: point,
                        scale: scale,
                        availableHeight: proxy.size.height
                    )
                }
            }
        }
        .frame(height: chartHeight)
        .padding(.horizontal, 2)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppStrings.localized("analytics.hourDistribution.accessibility.chart"))
    }

    private var hourAxis: some View {
        let markers = hourMarkers

        return HStack {
            ForEach(markers, id: \.self) { hour in
                Text(AnalyticsHourLabelFormatter.string(for: hour, calendar: calendar, locale: locale))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if hour != markers.last {
                    Spacer()
                }
            }
        }
        .accessibilityHidden(true)
    }
}

extension HourTaskSlice {
    var color: Color {
        Color(hex: colorHex) ?? .blue
    }
}

private struct TodayActivityHeader: View {
    let totalSeconds: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                trackedSummary
                Spacer(minLength: 12)
                taskColorHint
                    .multilineTextAlignment(.trailing)
            }

            VStack(alignment: .leading, spacing: 6) {
                trackedSummary
                taskColorHint
            }
        }
    }

    private var trackedSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(DurationFormatter.compact(totalSeconds))
                .font(.title3.weight(.semibold).monospacedDigit())
            Text(AppStrings.todayTracked)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var taskColorHint: some View {
        Text(AppStrings.localized("analytics.hourDistribution.taskColorHint"))
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
