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
                verticalTimeline
                    .frame(height: compactHeight)
            } else {
                TimelineChartHorizontalSizingLayout(
                    entries: laneEntries,
                    compression: axisCompression
                ) {
                    horizontalTimeline
                }
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
        GeometryReader { proxy in
            let barLayout = TimelineChartLayout.horizontalBars(
                entries: laneEntries,
                compression: axisCompression,
                width: proxy.size.width
            )
            let entryByID = Dictionary(
                uniqueKeysWithValues: laneEntries.map { ($0.id, $0) }
            )
            let gapByID = Dictionary(
                uniqueKeysWithValues: axisCompression.omittedGaps.map { ($0.id, $0) }
            )
            let gapLabelLayout = TimelineChartLayout.horizontalGapLabels(
                gaps: axisCompression.omittedGaps,
                compression: axisCompression,
                axisLength: barLayout.axisLength
            )
            let plotHeight = TimelineChartLayout.horizontalPlotHeight(
                height: proxy.size.height,
                gapLabelRowCount: gapLabelLayout.rowCount
            )
            let lanes = TimelineChartLayout.horizontalLanes(
                height: proxy.size.height,
                laneCount: barLayout.laneCount,
                gapLabelRowCount: gapLabelLayout.rowCount
            )

            ZStack(alignment: .topLeading) {
                horizontalHourGrid(
                    axisLength: barLayout.axisLength,
                    plotHeight: plotHeight,
                    gapLabelRowCount: gapLabelLayout.rowCount
                )
                ForEach(axisCompression.omittedGaps) { gap in
                    horizontalGapLine(
                        gap,
                        axisLength: barLayout.axisLength,
                        plotHeight: plotHeight
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
                ForEach(gapLabelLayout.placements) { placement in
                    if let gap = gapByID[placement.id] {
                        horizontalGapLabel(
                            gap,
                            placement: placement,
                            plotHeight: plotHeight
                        )
                        .zIndex(1)
                    }
                }
            }
        }
    }

    var verticalTimeline: some View {
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
                laneCount: barLayout.laneCount
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
                ForEach(axisCompression.omittedGaps) { gap in
                    verticalGapLabel(
                        gap,
                        axisLength: barLayout.axisLength
                    )
                    .zIndex(1)
                }
            }
        }
    }
}

private struct TimelineChartHorizontalSizingLayout: Layout {
    let entries: [AnalyticsTimelineEntry]
    let compression: TimelineAxisCompression

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard subviews.isEmpty == false else { return .zero }
        let width: CGFloat
        if let proposedWidth = proposal.width, proposedWidth.isFinite {
            width = max(0, proposedWidth)
        } else {
            width = 640
        }
        let bars = TimelineChartLayout.horizontalBars(
            entries: entries,
            compression: compression,
            width: width
        )
        let gapLabels = TimelineChartLayout.horizontalGapLabels(
            gaps: compression.omittedGaps,
            compression: compression,
            axisLength: bars.axisLength
        )
        return CGSize(
            width: width,
            height: TimelineChartLayout.horizontalTimelineHeight(
                laneCount: bars.laneCount,
                gapLabelRowCount: gapLabels.rowCount
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
