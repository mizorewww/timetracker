import SwiftUI

extension TimelineChart {
    /// Hour grid lines across the plot; `timeAxis` is the direction time
    /// runs, so the lines themselves are perpendicular to it.
    func hourGrid(
        timeAxis: Axis,
        axisLength: CGFloat,
        plotSize: CGSize
    ) -> some View {
        let ticks = switch timeAxis {
        case .horizontal:
            visibleHourTicks(axisLength: axisLength, minimumSpacing: 84)
        case .vertical:
            TimelineChartLayout.verticalAxisTicks(
                displayInterval: displayInterval,
                compression: axisCompression,
                axisLength: axisLength,
                minimumSpacing: 28
            )
        }
        return ZStack(alignment: .topLeading) {
            ForEach(ticks, id: \.date) { tick in
                TimelineGridLine(
                    position: axisLength * CGFloat(axisCompression.ratio(for: tick.date)),
                    isVertical: timeAxis == .horizontal
                )
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                .frame(width: plotSize.width, height: plotSize.height)
            }
        }
    }

    func horizontalHourLabels(axisLength: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(
                visibleHourTicks(axisLength: axisLength, minimumSpacing: 84),
                id: \.date
            ) { tick in
                let x = axisLength * CGFloat(axisCompression.ratio(for: tick.date))
                hourLabelText(tick)
                    .frame(width: 52, height: 20, alignment: .leading)
                    .offset(
                        x: TimelineChartLayout.axisLabelOrigin(
                            position: x,
                            axisLength: axisLength,
                            labelExtent: 52,
                            role: tick.role
                        )
                    )
            }
        }
    }

    func verticalHourLabels(
        width: CGFloat,
        axisLength: CGFloat,
        gapLabelHeight: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(
                TimelineChartLayout.verticalAxisTicks(
                    displayInterval: displayInterval,
                    compression: axisCompression,
                    axisLength: axisLength,
                    minimumSpacing: 28,
                    axisLabelWidth: width,
                    gapLabelHeight: gapLabelHeight
                ),
                id: \.date
            ) { tick in
                let ratio = axisCompression.ratio(for: tick.date)
                let y = axisLength * CGFloat(ratio)
                hourLabelText(tick)
                    .frame(
                        width: max(0, width - 12),
                        height: 16,
                        alignment: .leading
                    )
                    .offset(
                        y: TimelineChartLayout.axisLabelOrigin(
                            position: y,
                            axisLength: axisLength,
                            labelExtent: 16,
                            role: tick.role
                        )
                    )
            }
        }
    }

    private func hourLabelText(_ tick: TimelineChartAxisTick) -> some View {
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
    }

    /// Dashed marker for an omitted gap, perpendicular to `timeAxis`.
    func gapLine(
        _ gap: TimelineOmittedGap,
        timeAxis: Axis,
        axisLength: CGFloat,
        crossExtent: CGFloat
    ) -> some View {
        let ratio = axisCompression.ratio(forCompressedOffset: gap.compressedMidpointOffset)
        let position = min(max(0, axisLength * CGFloat(ratio)), max(0, axisLength - 1))
        let isHorizontal = timeAxis == .horizontal
        return DashedTimelineLine(isVertical: isHorizontal)
            .stroke(
                Color.secondary.opacity(0.42),
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )
            .frame(
                width: isHorizontal ? 1 : crossExtent,
                height: isHorizontal ? crossExtent : 1
            )
            .offset(x: isHorizontal ? position : 0, y: isHorizontal ? 0 : position)
    }

    func verticalGapConnector(descends: Bool) -> some View {
        VerticalGapConnector(descends: descends)
            .stroke(Color.secondary.opacity(0.32), lineWidth: 1)
    }

    func omittedGapLabel(_ gap: TimelineOmittedGap) -> some View {
        let text = omittedGapText(gap)
        return omittedGapTextContent(text)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule())
            .fixedSize(horizontal: true, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .accessibilityIdentifier("timeline.gap.\(gap.id)")
    }

    func omittedGapMeasurementLabel(_ gap: TimelineOmittedGap) -> some View {
        omittedGapTextContent(omittedGapText(gap))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .fixedSize(horizontal: true, vertical: true)
            .hidden()
            .accessibilityHidden(true)
    }

    private func omittedGapTextContent(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: true, vertical: true)
    }

    func omittedGapText(_ gap: TimelineOmittedGap) -> String {
        String(
            format: AppStrings.localized("analytics.timeline.gap.omitted"),
            DurationFormatter.compact(Int(gap.duration))
        )
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

private struct VerticalGapConnector: Shape {
    let descends: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(
            to: CGPoint(
                x: rect.minX,
                y: descends ? rect.minY : rect.maxY
            )
        )
        path.addLine(
            to: CGPoint(
                x: rect.maxX,
                y: descends ? rect.maxY : rect.minY
            )
        )
        return path
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
