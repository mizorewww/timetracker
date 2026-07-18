import SwiftUI

extension TimelineChart {
    func horizontalBar(
        entry: AnalyticsTimelineEntry,
        width: CGFloat
    ) -> some View {
        let startRatio = axisCompression.ratio(for: entry.interval.start)
        let endRatio = axisCompression.ratio(for: entry.interval.end)
        let durationRatio = max(0, endRatio - startRatio)
        let barWidth = max(18, width * CGFloat(durationRatio))
        let x = width * CGFloat(startRatio)

        return RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color(hex: entry.colorHex) ?? .blue)
            .frame(width: barWidth, height: 24)
            .overlay {
                Image(systemName: entry.iconName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .offset(x: x, y: CGFloat(entry.lane) * 34 + 16)
            .help("\(entry.title) \(shortRange(entry))")
    }

    func verticalBar(
        entry: AnalyticsTimelineEntry,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let startRatio = axisCompression.ratio(for: entry.interval.start)
        let endRatio = axisCompression.ratio(for: entry.interval.end)
        let durationRatio = max(0, endRatio - startRatio)
        let leftAxis: CGFloat = 68
        let laneWidth = max(
            22,
            min(38, (width - leftAxis - 12) / CGFloat(max(laneCount, 1)) - 8)
        )
        let barHeight = max(20, height * CGFloat(durationRatio))
        let x = leftAxis + CGFloat(entry.lane) * (laneWidth + 8)
        let y = height * CGFloat(startRatio)

        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(hex: entry.colorHex) ?? .blue)
            .frame(width: laneWidth, height: barHeight)
            .overlay(alignment: .top) {
                Image(systemName: entry.iconName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 4)
            }
            .offset(x: x, y: min(y, height - barHeight))
            .help("\(entry.title) \(shortRange(entry))")
    }

    private func shortRange(_ entry: AnalyticsTimelineEntry) -> String {
        "\(TimeDisplayFormatter.hourMinute(entry.startedAt))–\(TimeDisplayFormatter.hourMinute(entry.endedAt))"
    }
}
