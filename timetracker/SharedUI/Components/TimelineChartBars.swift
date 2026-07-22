import SwiftUI

extension TimelineChart {
    func horizontalBar(
        entry: AnalyticsTimelineEntry,
        placement: TimelineChartBarPlacement,
        lanes: TimelineChartLaneLayout
    ) -> some View {
        return RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color(hex: entry.colorHex) ?? .blue)
            .frame(width: placement.axisExtent, height: lanes.laneExtent)
            .overlay {
                barIcon(for: entry)
            }
            .offset(
                x: placement.axisOrigin,
                y: lanes.offset(for: placement.lane)
            )
            .help("\(entry.title) \(shortRange(entry))")
            .accessibilityElement(children: .contain)
            .accessibilityLabel(entry.title)
            .accessibilityHidden(!exposesUITestingMarks)
    }

    func verticalBar(
        entry: AnalyticsTimelineEntry,
        placement: TimelineChartBarPlacement,
        lanes: TimelineChartLaneLayout
    ) -> some View {
        let x = lanes.offset(for: placement.lane)

        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(hex: entry.colorHex) ?? .blue)
            .frame(width: lanes.laneExtent, height: placement.axisExtent)
            .overlay(alignment: .top) {
                barIcon(for: entry)
            }
            .offset(x: x, y: placement.axisOrigin)
            .help("\(entry.title) \(shortRange(entry))")
            .accessibilityElement(children: .contain)
            .accessibilityLabel(entry.title)
            .accessibilityHidden(!exposesUITestingMarks)
    }

    private func barIcon(
        for entry: AnalyticsTimelineEntry
    ) -> some View {
        Image(systemName: entry.iconName)
            .resizable()
            .scaledToFit()
            .frame(
                width: TimelineChartLayout.barIconExtent,
                height: TimelineChartLayout.barIconExtent
            )
            .accessibilityLabel("\(entry.title) icon")
            .accessibilityHidden(!exposesUITestingMarks)
            .frame(
                width: TimelineChartLayout.minimumBarFootprint,
                height: TimelineChartLayout.minimumBarFootprint
            )
            .foregroundStyle(
                TaskColorPalette.contrastingForegroundColor(for: entry.colorHex)
            )
    }

    private func shortRange(_ entry: AnalyticsTimelineEntry) -> String {
        "\(TimeDisplayFormatter.hourMinute(entry.startedAt))–\(TimeDisplayFormatter.hourMinute(entry.endedAt))"
    }
}
