import SwiftUI

extension TimelineChart {
    private static let horizontalTickSpacing: CGFloat = 84
    private static let verticalTickSpacing: CGFloat = 28
    private static let horizontalHourLabelWidth: CGFloat = 52
    private static let horizontalHourLabelHeight: CGFloat = 20
    private static let verticalHourLabelHeight: CGFloat = 16

    /// Hour grid lines (perpendicular to the time axis) and dashed omitted-gap
    /// markers across the plot.
    func drawGrid(
        _ axis: TimelineChartAxis,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let isHorizontal = axis == .horizontal
        let axisLength = TimelineChartLayout.axisLength(
            totalExtent: isHorizontal ? size.width : size.height
        )
        let ticks = isHorizontal
            ? TimelineChartLayout.axisTicks(
                displayInterval: model.displayInterval,
                compression: model.compression,
                axisLength: axisLength,
                minimumSpacing: Self.horizontalTickSpacing
            )
            : TimelineChartLayout.verticalAxisTicks(
                displayInterval: model.displayInterval,
                compression: model.compression,
                axisLength: axisLength,
                minimumSpacing: Self.verticalTickSpacing
            )

        var grid = Path()
        for tick in ticks {
            let position = min(
                max(0, axisLength * CGFloat(model.compression.ratio(for: tick.date))),
                axisLength
            )
            grid.addLine(across: size, at: position, isHorizontal: isHorizontal)
        }
        context.stroke(grid, with: .color(Color.secondary.opacity(0.16)), lineWidth: 1)

        var gapLines = Path()
        for gap in model.gaps {
            let ratio = model.compression.ratio(forCompressedOffset: gap.compressedMidpointOffset)
            let position = min(max(0, axisLength * CGFloat(ratio)), max(0, axisLength - 1))
            gapLines.addLine(across: size, at: position + 0.5, isHorizontal: isHorizontal)
        }
        context.stroke(
            gapLines,
            with: .color(Color.secondary.opacity(0.42)),
            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
        )
    }

    /// Hour labels along the axis. Decorative: the bars and the adjacent
    /// rows carry the exact times for accessibility.
    func drawHourLabels(
        _ axis: TimelineChartAxis,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        switch axis {
        case .horizontal:
            let axisLength = TimelineChartLayout.axisLength(totalExtent: size.width)
            let ticks = TimelineChartLayout.axisTicks(
                displayInterval: model.displayInterval,
                compression: model.compression,
                axisLength: axisLength,
                minimumSpacing: Self.horizontalTickSpacing
            )
            for tick in ticks {
                let origin = TimelineChartLayout.axisLabelOrigin(
                    position: axisLength * CGFloat(model.compression.ratio(for: tick.date)),
                    axisLength: axisLength,
                    labelExtent: Self.horizontalHourLabelWidth,
                    role: tick.role
                )
                context.draw(
                    hourLabelText(tick),
                    at: CGPoint(x: origin, y: Self.horizontalHourLabelHeight / 2),
                    anchor: .leading
                )
            }
        case .vertical:
            let axisLength = TimelineChartLayout.axisLength(totalExtent: size.height)
            let ticks = TimelineChartLayout.verticalAxisTicks(
                displayInterval: model.displayInterval,
                compression: model.compression,
                axisLength: axisLength,
                minimumSpacing: Self.verticalTickSpacing,
                axisLabelWidth: size.width
            )
            for tick in ticks {
                let origin = TimelineChartLayout.axisLabelOrigin(
                    position: axisLength * CGFloat(model.compression.ratio(for: tick.date)),
                    axisLength: axisLength,
                    labelExtent: Self.verticalHourLabelHeight,
                    role: tick.role
                )
                context.draw(
                    hourLabelText(tick),
                    at: CGPoint(x: 0, y: origin + Self.verticalHourLabelHeight / 2),
                    anchor: .leading
                )
            }
        }
    }

    private func hourLabelText(_ tick: TimelineChartAxisTick) -> Text {
        Text(TimeDisplayFormatter.hourMinute(tick.date))
            .font(
                .footnote
                    .weight(tick.role.isBoundary ? .semibold : .regular)
                    .monospacedDigit()
            )
            .foregroundStyle(tick.role.isBoundary ? Color.primary : Color.secondary)
    }

    func verticalGapConnector(descends: Bool) -> some View {
        VerticalGapConnector(descends: descends)
            .stroke(Color.secondary.opacity(0.32), lineWidth: 1)
    }

    func omittedGapLabel(_ gap: TimelineOmittedGap) -> some View {
        let text = String(
            format: AppStrings.localized("analytics.timeline.gap.omitted"),
            DurationFormatter.compact(Int(gap.duration))
        )
        return Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule())
            .fixedSize(horizontal: true, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .accessibilityIdentifier("timeline.gap.\(gap.id)")
    }
}

private extension Path {
    /// A full-length line perpendicular to the time axis at `position`.
    mutating func addLine(across size: CGSize, at position: CGFloat, isHorizontal: Bool) {
        if isHorizontal {
            move(to: CGPoint(x: position, y: 0))
            addLine(to: CGPoint(x: position, y: size.height))
        } else {
            move(to: CGPoint(x: 0, y: position))
            addLine(to: CGPoint(x: size.width, y: position))
        }
    }
}

private struct VerticalGapConnector: Shape {
    let descends: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: descends ? rect.minY : rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: descends ? rect.maxY : rect.minY))
        return path
    }
}
