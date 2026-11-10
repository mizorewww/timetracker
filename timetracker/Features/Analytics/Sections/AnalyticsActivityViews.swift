import Charts
import Foundation
import SwiftUI

struct TodayActivityContent: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 150
    let activity: [HourTaskActivity]

    private static let minimumUpperBoundSeconds = 3600

    private var totalSeconds: Int {
        activity.reduce(0) { $0 + $1.totalSeconds }
    }

    private var upperBoundSeconds: Int {
        max(
            Self.minimumUpperBoundSeconds,
            activity.map(\.totalSeconds).max() ?? 0
        )
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
                return lhs.taskID < rhs.taskID
            }
            return lhs.seconds > rhs.seconds
        }
        .prefix(6)
        .map { $0 }
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

                activityChart

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

    private var activityChart: some View {
        let maxSeconds = upperBoundSeconds
        return Chart {
            ForEach(activity) { point in
                BarMark(
                    x: .value("Hour", point.hour),
                    yStart: .value("Start", 0),
                    yEnd: .value("Capacity", maxSeconds),
                    width: .ratio(0.78)
                )
                .foregroundStyle(Color.secondary.opacity(0.10))
                .cornerRadius(4)
                .accessibilityHidden(true)

                ForEach(point.slices.filter { $0.seconds > 0 }) { slice in
                    BarMark(
                        x: .value(
                            String.localizedStringWithFormat(
                                AppStrings.localized("analytics.hourDistribution.accessibility.hour"),
                                AnalyticsHourLabelFormatter.string(
                                    for: point.hour,
                                    calendar: calendar,
                                    locale: locale
                                )
                            ),
                            point.hour
                        ),
                        y: .value(slice.title, slice.seconds),
                        width: .ratio(0.78)
                    )
                    .foregroundStyle(slice.color)
                    .cornerRadius(3)
                    .accessibilityLabel(
                        String.localizedStringWithFormat(
                            AppStrings.localized("analytics.hourDistribution.accessibility.hour"),
                            AnalyticsHourLabelFormatter.string(
                                for: point.hour,
                                calendar: calendar,
                                locale: locale
                            )
                        )
                    )
                    .accessibilityValue(
                        String.localizedStringWithFormat(
                            AppStrings.localized("analytics.hourDistribution.accessibility.task"),
                            slice.title,
                            DurationFormatter.compact(slice.seconds, locale: locale)
                        )
                    )
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: 0 ... maxSeconds)
        .frame(maxWidth: .infinity)
        .frame(height: chartHeight)
        .padding(.horizontal, 4)
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

enum AnalyticsHourLabelFormatter {
    static func string(for hour: Int, calendar: Calendar, locale: Locale) -> String {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = 2001
        components.month = 1
        components.day = hour >= 24 ? 2 : 1
        components.hour = hour % 24

        guard let date = calendar.date(from: components) else {
            return hour.formatted(.number.locale(locale).grouping(.never))
        }
        return date.formatted(
            Date.FormatStyle(
                locale: locale,
                calendar: calendar,
                timeZone: calendar.timeZone
            )
            .hour(.defaultDigits(amPM: .abbreviated))
        )
    }
}

struct AnalyticsLegendSwatch: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
