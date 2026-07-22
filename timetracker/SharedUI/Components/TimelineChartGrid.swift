import SwiftUI
extension TimelineChart {
    func horizontalHourGrid(
        axisLength: CGFloat,
        plotHeight: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(
                visibleHourTicks(axisLength: axisLength, minimumSpacing: 84),
                id: \.date
            ) { tick in
                let ratio = axisCompression.ratio(for: tick.date)
                let x = axisLength * CGFloat(ratio)
                TimelineGridLine(position: x, isVertical: true)
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                    .frame(width: axisLength, height: plotHeight)
            }
        }
    }

    func horizontalHourLabels(axisLength: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(
                visibleHourTicks(axisLength: axisLength, minimumSpacing: 84),
                id: \.date
            ) { tick in
                let ratio = axisCompression.ratio(for: tick.date)
                let x = axisLength * CGFloat(ratio)
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
                            axisLength: axisLength,
                            labelExtent: 52,
                            role: tick.role
                        )
                    )
            }
        }
    }

    func verticalHourGrid(width: CGFloat, axisLength: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(
                TimelineChartLayout.verticalAxisTicks(
                    displayInterval: displayInterval,
                    compression: axisCompression,
                    axisLength: axisLength,
                    minimumSpacing: 28
                ),
                id: \.date
            ) { tick in
                let ratio = axisCompression.ratio(for: tick.date)
                let y = axisLength * CGFloat(ratio)
                TimelineGridLine(position: y, isVertical: false)
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                    .frame(width: width, height: axisLength)
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
                    .frame(
                        width: max(0, width - 12),
                        height: 16,
                        alignment: .trailing
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
    func horizontalGapLine(
        _ gap: TimelineOmittedGap,
        axisLength: CGFloat,
        plotHeight: CGFloat
    ) -> some View {
        let x = axisLength * CGFloat(
            axisCompression.ratio(forCompressedOffset: gap.compressedMidpointOffset)
        )
        return DashedTimelineLine(isVertical: true)
            .stroke(
                Color.secondary.opacity(0.42),
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )
            .frame(width: 1, height: plotHeight)
            .offset(x: min(max(0, x), max(0, axisLength - 1)))
    }

    func verticalGapLine(
        _ gap: TimelineOmittedGap,
        width: CGFloat,
        axisLength: CGFloat
    ) -> some View {
        let y = axisLength * CGFloat(
            axisCompression.ratio(forCompressedOffset: gap.compressedMidpointOffset)
        )
        return DashedTimelineLine(isVertical: false)
            .stroke(
                Color.secondary.opacity(0.42),
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )
            .frame(width: width, height: 1)
            .offset(
                y: min(max(0, y), max(0, axisLength - 1))
            )
    }

    func verticalGapConnector(descends: Bool) -> some View {
        VerticalGapConnector(descends: descends)
            .stroke(Color.secondary.opacity(0.32), lineWidth: 1)
    }

    @ViewBuilder
    func omittedGapLabel(_ gap: TimelineOmittedGap) -> some View {
        let text = omittedGapText(gap)
        let label = omittedGapLabelText(gap, text: text)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule())
            .fixedSize(horizontal: true, vertical: true)

        if exposesUITestingMarks {
            label
                .overlay {
                    gapGeometryProbe(
                        identifier: "timeline.gapCapsule.\(gap.id)",
                        label: text
                    )
                }
                .accessibilityElement(children: .contain)
        } else {
            label
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(text)
                .accessibilityIdentifier("timeline.gap.\(gap.id)")
        }
    }

    func omittedGapMeasurementLabel(_ gap: TimelineOmittedGap) -> some View {
        omittedGapTextContent(omittedGapText(gap))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .fixedSize(horizontal: true, vertical: true)
            .hidden()
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func omittedGapLabelText(
        _ gap: TimelineOmittedGap,
        text: String
    ) -> some View {
        let label = omittedGapTextContent(text)

        if exposesUITestingMarks {
            label
                .overlay {
                    gapGeometryProbe(
                        identifier: "timeline.gapText.\(gap.id)",
                        label: text
                    )
                }
                .overlay {
                    intrinsicGapTextGeometryProbe(gap, text: text)
                }
        } else {
            label
        }
    }

    private func intrinsicGapTextGeometryProbe(
        _ gap: TimelineOmittedGap,
        text: String
    ) -> some View {
        ZStack {
            Text(text)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
                .hidden()

            gapGeometryProbe(
                identifier: "timeline.gapIntrinsicText.\(gap.id)",
                label: text
            )
        }
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityElement(children: .contain)
    }

    private func omittedGapTextContent(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: true, vertical: true)
    }

    private func gapGeometryProbe(
        identifier: String,
        label: String
    ) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier)
            .allowsHitTesting(false)
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
