import Foundation
import SwiftUI

struct HourTaskActivityBar: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.displayScale) private var displayScale
    @Environment(\.locale) private var locale
    let point: HourTaskActivity
    let scale: HourActivityScale
    let availableHeight: CGFloat
    private let cornerRadius: CGFloat = 4

    private var targetHeight: CGFloat {
        CGFloat(
            scale.height(
                totalSeconds: point.totalSeconds,
                availableHeight: Double(max(0, availableHeight))
            )
        )
    }

    private var separatorHeight: CGFloat {
        1 / max(displayScale, 1)
    }

    private var renderedSlices: [RenderedHourTaskSlice] {
        let inputs = point.slices.map { HourStackLayoutInput(id: $0.id, seconds: $0.seconds) }
        let layouts = HourStackLayoutEngine.layout(
            inputs: inputs,
            availableHeight: Double(max(0, targetHeight)),
            minSliceHeight: 0
        )
        let slicesByID = point.slices.reduce(into: [UUID: HourTaskSlice]()) { result, slice in
            result[slice.id] = slice
        }
        return layouts.compactMap { layout in
            guard let slice = slicesByID[layout.id] else { return nil }
            return RenderedHourTaskSlice(slice: slice, height: CGFloat(layout.height))
        }
    }

    private var hourLabel: String {
        AnalyticsHourLabelFormatter.string(for: point.hour, calendar: calendar, locale: locale)
    }

    private var accessibilityValue: String {
        guard point.totalSeconds > 0 else {
            return AppStrings.localized("analytics.hourDistribution.accessibility.empty")
        }

        let total = String.localizedStringWithFormat(
            AppStrings.localized("analytics.hourDistribution.accessibility.total"),
            DurationFormatter.compact(point.totalSeconds, locale: locale)
        )
        let taskValues = point.slices
            .filter { $0.seconds > 0 }
            .map { slice in
                String.localizedStringWithFormat(
                    AppStrings.localized("analytics.hourDistribution.accessibility.task"),
                    slice.title,
                    DurationFormatter.compact(slice.seconds, locale: locale)
                )
            }

        guard !taskValues.isEmpty else { return total }
        let formatter = ListFormatter()
        formatter.locale = locale
        let tasks = formatter.string(from: taskValues) ?? taskValues.joined(separator: ", ")
        return "\(total). \(tasks)"
    }

    var body: some View {
        let slices = renderedSlices

        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if point.totalSeconds > 0, slices.isEmpty == false {
                VStack(spacing: 0) {
                    ForEach(Array(slices.reversed())) { rendered in
                        Rectangle()
                            .fill(rendered.slice.color)
                            .frame(height: rendered.height)
                            .overlay(alignment: .top) {
                                if rendered.id != slices.last?.id,
                                   rendered.height > separatorHeight * 2
                                {
                                    Color.primary.opacity(0.15)
                                        .frame(height: separatorHeight)
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: targetHeight, alignment: .bottom)
                .compositingGroup()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
        .help("\(hourLabel), \(DurationFormatter.compact(point.totalSeconds, locale: locale))")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String.localizedStringWithFormat(
                AppStrings.localized("analytics.hourDistribution.accessibility.hour"),
                hourLabel
            )
        )
        .accessibilityValue(accessibilityValue)
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

private struct RenderedHourTaskSlice: Identifiable {
    let slice: HourTaskSlice
    let height: CGFloat

    var id: UUID {
        slice.id
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
