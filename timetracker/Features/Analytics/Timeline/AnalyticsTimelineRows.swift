import SwiftUI

extension OverlappingTimelineCard {
    func horizontalBar(entry: AnalyticsTimelineEntry, width: CGFloat) -> some View {
        let interval = entry.interval
        let startRatio = axisCompression.ratio(for: interval.start)
        let endRatio = axisCompression.ratio(for: interval.end)
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

    func verticalBar(entry: AnalyticsTimelineEntry, width: CGFloat, height: CGFloat) -> some View {
        let interval = entry.interval
        let startRatio = axisCompression.ratio(for: interval.start)
        let endRatio = axisCompression.ratio(for: interval.end)
        let durationRatio = max(0, endRatio - startRatio)
        let leftAxis: CGFloat = 68
        let laneWidth = max(22, min(38, (width - leftAxis - 12) / CGFloat(max(laneCount, 1)) - 8))
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

    func timelineLegendRow(_ entry: AnalyticsTimelineEntry) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(hex: entry.colorHex) ?? .blue)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: entry.iconName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(entry.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(shortRange(entry))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(DurationFormatter.compact(entry.durationSeconds))
                    .font(.subheadline.monospacedDigit())
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 9)
    }

    func shortRange(_ entry: AnalyticsTimelineEntry) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: entry.startedAt))-\(formatter.string(from: entry.endedAt))"
    }
}
