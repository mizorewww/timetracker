import SwiftUI
extension TimelineChart {
    func horizontalHourGrid(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(
                visibleHourTicks(axisLength: width, minimumSpacing: 84),
                id: \.date
            ) { tick in
                let ratio = axisCompression.ratio(for: tick.date)
                let x = width * CGFloat(ratio)
                TimelineGridLine(position: x, isVertical: true)
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                    .frame(width: width, height: max(0, height - 24))
                Text(hourLabel(tick.date))
                    .font(
                        .footnote
                            .weight(tick.role.isBoundary ? .semibold : .regular)
                            .monospacedDigit()
                    )
                    .foregroundStyle(
                        tick.role.isBoundary ? Color.primary : Color.secondary
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.92)
                    .frame(width: 52, height: 20, alignment: .leading)
                    .offset(
                        x: TimelineChartLayout.axisLabelOrigin(
                            position: x,
                            axisLength: width,
                            labelExtent: 52,
                            role: tick.role
                        ),
                        y: max(0, height - 20)
                    )
            }
        }
    }
    func verticalHourGrid(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(
                visibleHourTicks(axisLength: height, minimumSpacing: 28),
                id: \.date
            ) { tick in
                let ratio = axisCompression.ratio(for: tick.date)
                let y = height * CGFloat(ratio)
                TimelineGridLine(position: y, isVertical: false)
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                    .frame(width: max(0, width - 68), height: height)
                    .offset(x: 68)
                Text(hourLabel(tick.date))
                    .font(
                        .footnote
                            .weight(tick.role.isBoundary ? .semibold : .regular)
                            .monospacedDigit()
                    )
                    .foregroundStyle(
                        tick.role.isBoundary ? Color.primary : Color.secondary
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.92)
                    .frame(width: 56, height: 16, alignment: .trailing)
                    .offset(
                        y: TimelineChartLayout.axisLabelOrigin(
                            position: y,
                            axisLength: height,
                            labelExtent: 16,
                            role: tick.role
                        )
                    )
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

    private func visibleHourTicks(
        axisLength: CGFloat,
        minimumSpacing: CGFloat
    ) -> [TimelineChartAxisTick] {
        TimelineChartLayout.axisTicks(
            displayInterval: displayInterval,
            compression: axisCompression,
            axisLength: axisLength,
            minimumSpacing: minimumSpacing
        )
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
private struct TimelineGridLine: Shape {
    let position: CGFloat
    let isVertical: Bool

    func path(in rect: CGRect) -> Path {
        let coordinate = min(
            max(0, position),
            isVertical ? rect.width : rect.height
        )
        var path = Path()
        if isVertical {
            path.move(to: CGPoint(x: coordinate, y: rect.minY))
            path.addLine(to: CGPoint(x: coordinate, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: coordinate))
            path.addLine(to: CGPoint(x: rect.maxX, y: coordinate))
        }
        return path
    }
}
