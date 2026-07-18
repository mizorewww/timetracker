import SwiftUI

extension TimelineChart {
    func horizontalHourGrid(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(visibleHourTicks, id: \.self) { tick in
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
            ForEach(visibleHourTicks, id: \.self) { tick in
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

    func horizontalGapMarker(
        _ gap: TimelineOmittedGap,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let x = width * CGFloat(
            axisCompression.ratio(forCompressedOffset: gap.compressedMidpointOffset)
        )
        return DashedTimelineLine(isVertical: true)
            .stroke(
                Color.secondary.opacity(0.42),
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )
            .frame(width: 1, height: max(28, height - 28))
            .overlay(alignment: .center) {
                omittedGapLabel(gap)
            }
            .offset(x: min(max(0, x), width - 1), y: 4)
    }

    func verticalGapMarker(
        _ gap: TimelineOmittedGap,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let y = height * CGFloat(
            axisCompression.ratio(forCompressedOffset: gap.compressedMidpointOffset)
        )
        return DashedTimelineLine(isVertical: false)
            .stroke(
                Color.secondary.opacity(0.42),
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )
            .frame(width: max(40, width - 68), height: 1)
            .overlay(alignment: .center) {
                omittedGapLabel(gap)
            }
            .offset(x: 68, y: min(max(0, y), height - 1))
    }

    private func omittedGapLabel(_ gap: TimelineOmittedGap) -> some View {
        Text(
            String(
                format: AppStrings.localized("analytics.timeline.gap.omitted"),
                DurationFormatter.compact(Int(gap.duration))
            )
        )
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.regularMaterial, in: Capsule())
        .fixedSize()
    }

    private var visibleHourTicks: [Date] {
        hourTicks().filter { !axisCompression.isInsideOmittedGap($0) }
    }

    private func hourTicks() -> [Date] {
        let calendar = Calendar.current
        let totalHours = max(1, displayInterval.duration / 3_600)
        let step = totalHours <= 4 ? 1 : (totalHours <= 10 ? 2 : 4)
        let firstHour = calendar.dateInterval(of: .hour, for: displayInterval.start)?.start
            ?? displayInterval.start
        var tick = firstHour
        var result: [Date] = []
        while tick <= displayInterval.end {
            if tick >= displayInterval.start {
                result.append(tick)
            }
            guard let next = calendar.date(byAdding: .hour, value: step, to: tick) else {
                break
            }
            tick = next
        }
        if result.isEmpty || result.last! < displayInterval.end {
            result.append(displayInterval.end)
        }
        return result
    }

    private func hourLabel(_ date: Date) -> String {
        TimeDisplayFormatter.hourMinute(date)
    }
}

private struct DashedTimelineLine: Shape {
    let isVertical: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if isVertical {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
        return path
    }
}
