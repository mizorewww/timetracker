import SwiftUI

struct TodayActivityContent: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
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
        .sorted { $0.seconds > $1.seconds }
        .prefix(6)
        .map { $0 }
    }

    var body: some View {
        if totalSeconds == 0 {
            EmptyStateRow(title: AppStrings.localized("analytics.empty.todayTaskTime"), icon: "chart.bar")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DurationFormatter.compact(totalSeconds))
                            .font(.title3.weight(.semibold).monospacedDigit())
                        Text(AppStrings.todayTracked)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(AppStrings.localized("analytics.hourDistribution.taskColorHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                activityBars

                HStack {
                    ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                        Text(AnalyticsHourLabelFormatter.string(for: hour, calendar: calendar, locale: locale))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if hour != 24 {
                            Spacer()
                        }
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(legendItems) { item in
                        AnalyticsLegendSwatch(color: item.color, title: item.title)
                    }
                }
            }
        }
    }

    private var activityBars: some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(activity) { point in
                    HourTaskActivityBar(
                        point: point,
                        availableHeight: proxy.size.height
                    )
                }
            }
        }
        .frame(height: 150)
        .padding(.horizontal, 2)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppStrings.localized("analytics.hourDistribution.accessibility.chart"))
    }

}

extension HourTaskSlice {
    var color: Color { Color(hex: colorHex) ?? .blue }
}
