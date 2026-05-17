import SwiftUI

extension OverlappingTimelineContent {
    var horizontalTimeline: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                horizontalHourGrid(width: proxy.size.width, height: proxy.size.height)
                ForEach(axisCompression.omittedGaps) { gap in
                    horizontalGapMarker(gap, width: proxy.size.width, height: proxy.size.height)
                }
                ForEach(laneEntries) { entry in
                    horizontalBar(entry: entry, width: proxy.size.width)
                }
            }
        }
    }

    var verticalTimeline: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                verticalHourGrid(width: proxy.size.width, height: proxy.size.height)
                ForEach(axisCompression.omittedGaps) { gap in
                    verticalGapMarker(gap, width: proxy.size.width, height: proxy.size.height)
                }
                ForEach(laneEntries) { entry in
                    verticalBar(entry: entry, width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
    }

    func horizontalHourGrid(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(hourTicks().filter { !axisCompression.isInsideOmittedGap($0) }, id: \.self) { tick in
                let ratio = axisCompression.ratio(for: tick)
                let x = width * CGFloat(ratio)
                VStack(alignment: .leading, spacing: 4) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.16))
                        .frame(width: 1, height: height - 24)
                    Text(hourLabel(tick))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.92)
                        .frame(width: 52, alignment: .leading)
                }
                .offset(x: min(max(0, x), width - 52))
            }
        }
    }

    func verticalHourGrid(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(hourTicks().filter { !axisCompression.isInsideOmittedGap($0) }, id: \.self) { tick in
                let ratio = axisCompression.ratio(for: tick)
                let y = height * CGFloat(ratio)
                HStack(spacing: 8) {
                    Text(hourLabel(tick))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.92)
                        .frame(width: 56, alignment: .trailing)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.16))
                        .frame(height: 1)
                }
                .offset(y: min(max(0, y - 6), height - 12))
            }
        }
    }

    func horizontalGapMarker(_ gap: TimelineOmittedGap, width: CGFloat, height: CGFloat) -> some View {
        let x = width * CGFloat(axisCompression.ratio(forCompressedOffset: gap.compressedMidpointOffset))
        return DashedTimelineLine(isVertical: true)
            .stroke(Color.secondary.opacity(0.42), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(width: 1, height: max(28, height - 28))
            .overlay(alignment: .center) {
                Text(omittedGapText(gap))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.regularMaterial, in: Capsule())
                    .fixedSize()
            }
            .offset(x: min(max(0, x), width - 1), y: 4)
    }

    func verticalGapMarker(_ gap: TimelineOmittedGap, width: CGFloat, height: CGFloat) -> some View {
        let y = height * CGFloat(axisCompression.ratio(forCompressedOffset: gap.compressedMidpointOffset))
        return DashedTimelineLine(isVertical: false)
            .stroke(Color.secondary.opacity(0.42), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(width: max(40, width - 68), height: 1)
            .overlay(alignment: .center) {
                Text(omittedGapText(gap))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.regularMaterial, in: Capsule())
                    .fixedSize()
            }
            .offset(x: 68, y: min(max(0, y), height - 1))
    }

    func hourTicks() -> [Date] {
        let calendar = Calendar.current
        let totalHours = max(1, displayInterval.duration / 3600)
        let step: Int
        if totalHours <= 4 {
            step = 1
        } else if totalHours <= 10 {
            step = 2
        } else {
            step = 4
        }
        let firstHour = calendar.dateInterval(of: .hour, for: displayInterval.start)?.start ?? displayInterval.start
        var tick = firstHour
        var result: [Date] = []
        while tick <= displayInterval.end {
            if tick >= displayInterval.start {
                result.append(tick)
            }
            guard let next = calendar.date(byAdding: .hour, value: step, to: tick) else { break }
            tick = next
        }
        if result.isEmpty || result.last! < displayInterval.end {
            result.append(displayInterval.end)
        }
        return result
    }

    func hourLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    func omittedGapText(_ gap: TimelineOmittedGap) -> String {
        String(format: AppStrings.localized("analytics.timeline.gap.omitted"), DurationFormatter.compact(Int(gap.duration)))
    }
}
