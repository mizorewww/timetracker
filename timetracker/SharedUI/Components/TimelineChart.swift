import SwiftUI

/// One visual grammar for ledger time on Today and in Analytics.
///
/// Exact record values and actions stay in the adjacent feature-owned rows.
/// This component owns only the shared axis, overlap lanes, bars, and omitted
/// idle-gap presentation.
struct TimelineChart: View {
    let timeline: AnalyticsTimelineSnapshot
    var compactHeight: CGFloat = 360
    var exposesUITestingMarks = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if usesVerticalLayout {
                TimelineChartVerticalSizingLayout(
                    minimumHeight: compactHeight,
                    gapLabelCount: axisCompression.omittedGaps.count
                ) {
                    GeometryReader { viewport in
                        ScrollView(.horizontal) {
                            verticalTimeline
                                .frame(minWidth: viewport.size.width)
                                .frame(height: viewport.size.height)
                        }
                        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    }
                }
            } else {
                horizontalTimeline
            }
        }
        .accessibilityHidden(!exposesUITestingMarks)
    }

    var displayInterval: DateInterval {
        timeline.displayInterval
            ?? DateInterval(start: Date(timeIntervalSince1970: 0), duration: 1)
    }

    var laneEntries: [AnalyticsTimelineEntry] {
        timeline.entries
    }

    var axisCompression: TimelineAxisCompression {
        timeline.axisCompression
            ?? TimelineAxisCompression(displayInterval: displayInterval, busyIntervals: [])
    }

    private var usesVerticalLayout: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

}

extension TimelineChart {
    var horizontalTimeline: some View {
        TimelineChartHorizontalLayout(
            entries: laneEntries,
            gaps: axisCompression.omittedGaps,
            compression: axisCompression
        ) {
            horizontalPlot
                .timelineChartLayoutRole(.plot)

            ForEach(axisCompression.omittedGaps) { gap in
                omittedGapLabel(gap)
                    .timelineChartLayoutRole(.gapLabel(gap.id))
                    .zIndex(1)
            }

            horizontalAxisLabels
                .timelineChartLayoutRole(.axisLabels)
        }
    }

    private var horizontalPlot: some View {
        GeometryReader { proxy in
            let barLayout = TimelineChartLayout.horizontalBars(
                entries: laneEntries,
                compression: axisCompression,
                width: proxy.size.width
            )
            let entryByID = Dictionary(
                uniqueKeysWithValues: laneEntries.map { ($0.id, $0) }
            )
            let lanes = TimelineChartLayout.horizontalPlotLanes(
                height: proxy.size.height,
                laneCount: barLayout.laneCount
            )

            ZStack(alignment: .topLeading) {
                horizontalHourGrid(
                    axisLength: barLayout.axisLength,
                    plotHeight: proxy.size.height
                )
                ForEach(axisCompression.omittedGaps) { gap in
                    horizontalGapLine(
                        gap,
                        axisLength: barLayout.axisLength,
                        plotHeight: proxy.size.height
                    )
                }
                ForEach(barLayout.placements) { placement in
                    if let entry = entryByID[placement.id] {
                        horizontalBar(
                            entry: entry,
                            placement: placement,
                            lanes: lanes
                        )
                    }
                }
            }
        }
    }

    private var horizontalAxisLabels: some View {
        GeometryReader { proxy in
            let barLayout = TimelineChartLayout.horizontalBars(
                entries: laneEntries,
                compression: axisCompression,
                width: proxy.size.width
            )
            horizontalHourLabels(axisLength: barLayout.axisLength)
        }
    }

    var verticalTimeline: some View {
        let height = TimelineChartLayout.verticalTimelineHeight(
            minimumHeight: compactHeight,
            gapLabelCount: axisCompression.omittedGaps.count
        )
        let barLayout = TimelineChartLayout.verticalBars(
            entries: laneEntries,
            compression: axisCompression,
            height: height
        )
        let gapLabelLayout = TimelineChartLayout.verticalGapLabels(
            gaps: axisCompression.omittedGaps,
            compression: axisCompression,
            axisLength: barLayout.axisLength
        )
        let gapByID = Dictionary(
            uniqueKeysWithValues: axisCompression.omittedGaps.map { ($0.id, $0) }
        )

        return TimelineChartVerticalLayout(
            entries: laneEntries,
            gaps: axisCompression.omittedGaps,
            compression: axisCompression
        ) {
            verticalPlot
                .timelineChartLayoutRole(.plot)

            verticalAxisLabels
                .timelineChartLayoutRole(.axisLabels)

            ForEach(gapLabelLayout.placements) { placement in
                if let gap = gapByID[placement.id] {
                    omittedGapLabel(gap)
                        .timelineChartLayoutRole(.gapLabel(gap.id))
                        .zIndex(1)

                    verticalGapConnector(
                        descends: placement.anchorPosition >=
                            placement.axisOrigin + placement.axisExtent / 2
                    )
                    .timelineChartLayoutRole(.gapConnector(gap.id))
                }
            }
        }
    }

    private var verticalPlot: some View {
        GeometryReader { proxy in
            let barLayout = TimelineChartLayout.verticalBars(
                entries: laneEntries,
                compression: axisCompression,
                height: proxy.size.height
            )
            let entryByID = Dictionary(
                uniqueKeysWithValues: laneEntries.map { ($0.id, $0) }
            )
            let lanes = TimelineChartLayout.verticalLanes(
                width: proxy.size.width,
                laneCount: barLayout.laneCount,
                axisLabelWidth: 0
            )

            ZStack(alignment: .topLeading) {
                verticalHourGrid(
                    width: proxy.size.width,
                    axisLength: barLayout.axisLength
                )
                ForEach(axisCompression.omittedGaps) { gap in
                    verticalGapLine(
                        gap,
                        width: proxy.size.width,
                        axisLength: barLayout.axisLength
                    )
                }
                ForEach(barLayout.placements) { placement in
                    if let entry = entryByID[placement.id] {
                        verticalBar(
                            entry: entry,
                            placement: placement,
                            lanes: lanes
                        )
                    }
                }
            }
        }
    }

    private var verticalAxisLabels: some View {
        GeometryReader { proxy in
            let barLayout = TimelineChartLayout.verticalBars(
                entries: laneEntries,
                compression: axisCompression,
                height: proxy.size.height
            )
            verticalHourLabels(
                width: proxy.size.width,
                axisLength: barLayout.axisLength,
                gapLabelHeight: TimelineChartLayout.verticalGapLabelHeight
            )
        }
    }
}

private struct TimelineChartVerticalSizingLayout: Layout {
    let minimumHeight: CGFloat
    let gapLabelCount: Int

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard subviews.isEmpty == false else { return .zero }
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 320
        return CGSize(
            width: width,
            height: TimelineChartLayout.verticalTimelineHeight(
                minimumHeight: minimumHeight,
                gapLabelCount: gapLabelCount
            )
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        subview.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(
                width: bounds.width,
                height: bounds.height
            )
        )
    }
}

nonisolated private enum TimelineChartLayoutSubviewRole: Hashable {
    case content
    case plot
    case axisLabels
    case gapLabel(String)
    case gapConnector(String)
}

nonisolated private struct TimelineChartLayoutSubviewRoleKey: LayoutValueKey {
    static let defaultValue = TimelineChartLayoutSubviewRole.content
}

private extension View {
    func timelineChartLayoutRole(
        _ role: TimelineChartLayoutSubviewRole
    ) -> some View {
        layoutValue(key: TimelineChartLayoutSubviewRoleKey.self, value: role)
    }
}

private struct TimelineChartHorizontalLayout: Layout {
    let entries: [AnalyticsTimelineEntry]
    let gaps: [TimelineOmittedGap]
    let compression: TimelineAxisCompression

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard subviews.isEmpty == false else { return .zero }
        let width = finiteDimension(proposal.width, fallback: 640)
        let metrics = metrics(width: width, subviews: subviews)
        return CGSize(width: metrics.width, height: metrics.totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let metrics = metrics(width: bounds.width, subviews: subviews)

        for subview in subviews {
            switch subview[TimelineChartLayoutSubviewRoleKey.self] {
            case .plot:
                subview.place(
                    at: bounds.origin,
                    anchor: .topLeading,
                    proposal: ProposedViewSize(
                        width: metrics.width,
                        height: metrics.plotHeight
                    )
                )
            case .axisLabels:
                subview.place(
                    at: CGPoint(
                        x: bounds.minX,
                        y: bounds.minY + metrics.plotHeight +
                            metrics.gapAnnotationHeight
                    ),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(
                        width: metrics.width,
                        height: TimelineChartLayout.horizontalAxisLabelHeight
                    )
                )
            case .gapLabel(let id):
                guard let placement = metrics.gapLayout.placements.first(
                    where: { $0.id == id }
                ), let size = metrics.labelSizes[id] else {
                    continue
                }
                let rowOrigin = bounds.minY + metrics.plotHeight +
                    TimelineChartLayout.horizontalAnnotationSpacing +
                    CGFloat(placement.row) * (
                        metrics.labelHeight +
                            TimelineChartLayout.horizontalGapLabelRowSpacing
                    )
                subview.place(
                    at: CGPoint(
                        x: bounds.minX + placement.axisOrigin +
                            placement.axisExtent / 2,
                        y: rowOrigin + metrics.labelHeight / 2
                    ),
                    anchor: .center,
                    proposal: ProposedViewSize(
                        width: size.width,
                        height: size.height
                    )
                )
            case .content, .gapConnector:
                continue
            }
        }
    }

    private func metrics(
        width: CGFloat,
        subviews: Subviews
    ) -> HorizontalMetrics {
        let safeWidth = max(0, width.isFinite ? width : 0)
        let bars = TimelineChartLayout.horizontalBars(
            entries: entries,
            compression: compression,
            width: safeWidth
        )
        let labelSizes = measuredGapLabelSizes(in: subviews)
        let gapLayout = TimelineChartLayout.horizontalGapLabels(
            gaps: gaps,
            compression: compression,
            axisLength: bars.axisLength,
            labelWidths: labelSizes.mapValues(\.width)
        )
        let labelHeight = labelSizes.values.map(\.height).max() ?? 0
        let plotHeight = TimelineChartLayout.horizontalPlotHeight(
            laneCount: bars.laneCount
        )
        let gapAnnotationHeight = TimelineChartLayout.horizontalGapAnnotationHeight(
            rowCount: gapLayout.rowCount,
            labelHeight: labelHeight
        )
        return HorizontalMetrics(
            width: safeWidth,
            plotHeight: plotHeight,
            labelHeight: labelHeight,
            gapAnnotationHeight: gapAnnotationHeight,
            totalHeight: plotHeight + gapAnnotationHeight +
                TimelineChartLayout.horizontalAxisLabelHeight,
            labelSizes: labelSizes,
            gapLayout: gapLayout
        )
    }

    private struct HorizontalMetrics {
        let width: CGFloat
        let plotHeight: CGFloat
        let labelHeight: CGFloat
        let gapAnnotationHeight: CGFloat
        let totalHeight: CGFloat
        let labelSizes: [String: CGSize]
        let gapLayout: TimelineChartHorizontalGapLabelLayout
    }
}

private struct TimelineChartVerticalLayout: Layout {
    let entries: [AnalyticsTimelineEntry]
    let gaps: [TimelineOmittedGap]
    let compression: TimelineAxisCompression

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard subviews.isEmpty == false else { return .zero }
        let metrics = metrics(
            proposedWidth: proposal.width,
            height: finiteDimension(proposal.height, fallback: 360),
            subviews: subviews
        )
        return CGSize(width: metrics.width, height: metrics.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let metrics = metrics(
            proposedWidth: bounds.width,
            height: bounds.height,
            subviews: subviews
        )

        for subview in subviews {
            switch subview[TimelineChartLayoutSubviewRoleKey.self] {
            case .plot:
                subview.place(
                    at: CGPoint(
                        x: bounds.minX + metrics.axisLabelWidth,
                        y: bounds.minY
                    ),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(
                        width: max(0, metrics.width - metrics.axisLabelWidth),
                        height: metrics.height
                    )
                )
            case .axisLabels:
                subview.place(
                    at: bounds.origin,
                    anchor: .topLeading,
                    proposal: ProposedViewSize(
                        width: metrics.axisLabelWidth,
                        height: metrics.height
                    )
                )
            case .gapLabel(let id):
                guard let placement = metrics.gapLayout.placements.first(
                    where: { $0.id == id }
                ), let size = metrics.labelSizes[id] else {
                    continue
                }
                subview.place(
                    at: CGPoint(
                        x: bounds.minX + metrics.axisLabelWidth / 2,
                        y: bounds.minY + placement.axisOrigin +
                            placement.axisExtent / 2
                    ),
                    anchor: .center,
                    proposal: ProposedViewSize(
                        width: size.width,
                        height: size.height
                    )
                )
            case .gapConnector(let id):
                guard let placement = metrics.gapLayout.placements.first(
                    where: { $0.id == id }
                ), let size = metrics.labelSizes[id] else {
                    continue
                }
                let labelTrailing = bounds.minX +
                    (metrics.axisLabelWidth + size.width) / 2
                let labelMidY = bounds.minY + placement.axisOrigin +
                    placement.axisExtent / 2
                let anchorY = bounds.minY + placement.anchorPosition
                subview.place(
                    at: CGPoint(
                        x: labelTrailing,
                        y: min(labelMidY, anchorY)
                    ),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(
                        width: max(
                            1,
                            bounds.minX + metrics.axisLabelWidth - labelTrailing
                        ),
                        height: max(1, abs(anchorY - labelMidY))
                    )
                )
            case .content:
                continue
            }
        }
    }

    private func metrics(
        proposedWidth: CGFloat?,
        height: CGFloat,
        subviews: Subviews
    ) -> VerticalMetrics {
        let safeHeight = max(0, height.isFinite ? height : 0)
        let bars = TimelineChartLayout.verticalBars(
            entries: entries,
            compression: compression,
            height: safeHeight
        )
        let labelSizes = measuredGapLabelSizes(in: subviews)
        let labelHeight = max(
            TimelineChartLayout.verticalGapLabelHeight,
            labelSizes.values.map(\.height).max() ?? 0
        )
        let gapLayout = TimelineChartLayout.verticalGapLabels(
            gaps: gaps,
            compression: compression,
            axisLength: bars.axisLength,
            labelHeight: labelHeight
        )
        let axisLabelWidth = TimelineChartLayout.verticalAxisLabelWidth(
            for: labelSizes.values.map(\.width)
        )
        let minimumWidth = TimelineChartLayout.verticalMinimumContentWidth(
            laneCount: bars.laneCount,
            axisLabelWidth: axisLabelWidth
        )
        let width = max(
            minimumWidth,
            finiteDimension(proposedWidth, fallback: 320)
        )
        return VerticalMetrics(
            width: width,
            height: safeHeight,
            axisLabelWidth: axisLabelWidth,
            labelSizes: labelSizes,
            gapLayout: gapLayout
        )
    }

    private struct VerticalMetrics {
        let width: CGFloat
        let height: CGFloat
        let axisLabelWidth: CGFloat
        let labelSizes: [String: CGSize]
        let gapLayout: TimelineChartVerticalGapLabelLayout
    }
}

private func measuredGapLabelSizes(
    in subviews: LayoutSubviews
) -> [String: CGSize] {
    subviews.reduce(into: [:]) { result, subview in
        guard case .gapLabel(let id) =
                subview[TimelineChartLayoutSubviewRoleKey.self] else {
            return
        }
        let measured = subview.sizeThatFits(.unspecified)
        result[id] = CGSize(
            width: measured.width.isFinite ? max(0, measured.width) : 0,
            height: measured.height.isFinite ? max(0, measured.height) : 0
        )
    }
}

private func finiteDimension(
    _ value: CGFloat?,
    fallback: CGFloat
) -> CGFloat {
    guard let value, value.isFinite else { return max(0, fallback) }
    return max(0, value)
}
