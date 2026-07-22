import SwiftUI

extension TimelineChart {
    func horizontalBar(
        entry: AnalyticsTimelineEntry,
        width: CGFloat,
        lanes: TimelineChartLaneLayout
    ) -> some View {
        let startRatio = axisCompression.ratio(for: entry.interval.start)
        let endRatio = axisCompression.ratio(for: entry.interval.end)
        let durationRatio = max(0, endRatio - startRatio)
        let barWidth = max(18, width * CGFloat(durationRatio))
        let x = width * CGFloat(startRatio)

        return RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color(hex: entry.colorHex) ?? .blue)
            .frame(width: barWidth, height: lanes.laneExtent)
            .overlay {
                Image(systemName: entry.iconName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        TaskColorPalette.contrastingForegroundColor(for: entry.colorHex)
                    )
            }
            .offset(x: x, y: lanes.offset(for: entry.lane))
            .help("\(entry.title) \(shortRange(entry))")
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
                Image(systemName: entry.iconName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(
                        TaskColorPalette.contrastingForegroundColor(for: entry.colorHex)
                    )
                    .padding(.top, 4)
            }
            .offset(x: x, y: placement.axisOrigin)
            .help("\(entry.title) \(shortRange(entry))")
    }

    private func shortRange(_ entry: AnalyticsTimelineEntry) -> String {
        "\(TimeDisplayFormatter.hourMinute(entry.startedAt))–\(TimeDisplayFormatter.hourMinute(entry.endedAt))"
    }
}
