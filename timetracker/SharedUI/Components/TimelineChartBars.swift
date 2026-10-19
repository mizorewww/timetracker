import SwiftUI

extension TimelineChart {
    /// One ledger mark; `TimelineChartBarsLayout` sizes and places it.
    func bar(
        _ entry: AnalyticsTimelineEntry,
        axis: TimelineChartAxis
    ) -> some View {
        RoundedRectangle(cornerRadius: axis == .horizontal ? 5 : 6, style: .continuous)
            .fill(Color(hex: entry.colorHex) ?? .blue)
            .overlay(alignment: axis == .horizontal ? .center : .top) {
                barIcon(for: entry)
            }
            .help("\(entry.title) \(shortRange(entry))")
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("timeline.bar.\(entry.id.stableSortKey)")
            .accessibilityLabel(entry.title)
            .accessibilityValue(shortRange(entry))
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
            .accessibilityHidden(true)
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
