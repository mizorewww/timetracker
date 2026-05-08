import SwiftUI

extension OverlappingTimelineCard {
    func horizontalBar(entry: TimelineLaneEntry, width: CGFloat) -> some View {
        let segment = entry.segment
        let interval = entry.interval
        let startRatio = axisCompression.ratio(for: interval.start)
        let endRatio = axisCompression.ratio(for: interval.end)
        let durationRatio = max(0, endRatio - startRatio)
        let task = store.task(for: segment.taskID)
        let barWidth = max(18, width * CGFloat(durationRatio))
        let x = width * CGFloat(startRatio)

        return RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color(hex: task?.colorHex) ?? .blue)
            .frame(width: barWidth, height: 24)
            .overlay {
                Image(systemName: task?.iconName ?? "checkmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .offset(x: x, y: CGFloat(entry.lane) * 34 + 16)
            .help("\(store.displayTitle(for: segment)) \(shortRange(segment))")
    }

    func verticalBar(entry: TimelineLaneEntry, width: CGFloat, height: CGFloat) -> some View {
        let segment = entry.segment
        let interval = entry.interval
        let startRatio = axisCompression.ratio(for: interval.start)
        let endRatio = axisCompression.ratio(for: interval.end)
        let durationRatio = max(0, endRatio - startRatio)
        let task = store.task(for: segment.taskID)
        let leftAxis: CGFloat = 68
        let laneWidth = max(22, min(38, (width - leftAxis - 12) / CGFloat(max(laneCount, 1)) - 8))
        let barHeight = max(20, height * CGFloat(durationRatio))
        let x = leftAxis + CGFloat(entry.lane) * (laneWidth + 8)
        let y = height * CGFloat(startRatio)

        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(hex: task?.colorHex) ?? .blue)
            .frame(width: laneWidth, height: barHeight)
            .overlay(alignment: .top) {
                Image(systemName: task?.iconName ?? "checkmark.circle")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 4)
            }
            .offset(x: x, y: min(y, height - barHeight))
            .help("\(store.displayTitle(for: segment)) \(shortRange(segment))")
    }

    func timelineLegendRow(_ segment: TimeSegment) -> some View {
        let task = store.task(for: segment.taskID)
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(hex: task?.colorHex) ?? .blue)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: task?.iconName ?? "checkmark.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(store.displayTitle(for: segment))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(displayPathText(for: segment))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(shortRange(segment))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(DurationFormatter.compact(Int((segment.endedAt ?? now).timeIntervalSince(segment.startedAt))))
                    .font(.subheadline.monospacedDigit())
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 9)
    }

    func shortRange(_ segment: TimeSegment) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: segment.startedAt))-\(segment.endedAt.map { formatter.string(from: $0) } ?? AppStrings.localized("common.now"))"
    }

    func displayPathText(for segment: TimeSegment) -> String {
        let path = store.displayPath(for: segment).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? AppStrings.rootTask : path
    }
}
