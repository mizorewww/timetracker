import SwiftUI

/// One visual grammar for ledger time on Today and in Analytics.
///
/// Exact record values and actions stay in the adjacent feature-owned rows.
/// This component owns only the shared axis, overlap lanes, bars, and omitted
/// idle-gap presentation.
struct TimelineChart: View {
    let timeline: AnalyticsTimelineSnapshot
    var compactHeight: CGFloat = 360
    @Environment(\.layoutShell) private var layoutShell
    @State var model = TimelineChartModel()

    var body: some View {
        let _ = model.update(timeline)
        Group {
            // Time runs down the screen when the chart is in a narrow column
            // and across it when there is room. Keyed off the root shell, not
            // the platform: a narrow Mac window and an iPad in Split View get
            // the vertical timeline for the same reason iPhone does.
            if layoutShell == .compact {
                verticalTimeline
            } else {
                horizontalTimeline
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Per-chart memo of everything derived from one snapshot.
///
/// The Layout passes, the plot, and the gap labels all need the bar
/// projection for the same axis length; tab-switch animations repeat those
/// passes, and projecting 600+ entries each time stalls the switch. The memo
/// is refreshed once per body evaluation (snapshot arrays compare by storage
/// identity first, so an unchanged cached snapshot costs O(1)) and every
/// layout pass reads it without comparing or rebuilding lookups.
final class TimelineChartModel {
    private struct BarKey: Hashable {
        let axis: TimelineChartAxis
        let totalExtent: CGFloat
    }

    private static let maximumRetainedLengths = 8

    private var timeline: AnalyticsTimelineSnapshot?
    /// Bumped whenever the snapshot changes; layouts carry it so SwiftUI sees
    /// a changed layout value and re-runs placement.
    private(set) var revision = 0
    private(set) var entries: [AnalyticsTimelineEntry] = []
    private(set) var displayInterval = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 1)
    private(set) var compression = TimelineAxisCompression(
        displayInterval: DateInterval(start: Date(timeIntervalSince1970: 0), duration: 1),
        busyIntervals: []
    )
    private(set) var gapByID: [String: TimelineOmittedGap] = [:]
    private var barLayouts: [BarKey: TimelineChartBarLayout] = [:]

    var gaps: [TimelineOmittedGap] {
        compression.omittedGaps
    }

    func update(_ timeline: AnalyticsTimelineSnapshot) {
        guard timeline != self.timeline else { return }
        self.timeline = timeline
        revision &+= 1
        var seenIDs = Set<TimelineEntryID>()
        entries = timeline.entries.filter { seenIDs.insert($0.id).inserted }
        displayInterval = timeline.displayInterval
            ?? DateInterval(start: Date(timeIntervalSince1970: 0), duration: 1)
        compression = timeline.axisCompression
            ?? TimelineAxisCompression(displayInterval: displayInterval, busyIntervals: [])
        gapByID = Dictionary(
            compression.omittedGaps.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        barLayouts.removeAll(keepingCapacity: true)
    }

    func bars(
        _ axis: TimelineChartAxis,
        totalExtent: CGFloat
    ) -> TimelineChartBarLayout {
        let key = BarKey(axis: axis, totalExtent: totalExtent)
        if let cached = barLayouts[key] {
            return cached
        }
        if barLayouts.count >= Self.maximumRetainedLengths {
            barLayouts.removeAll(keepingCapacity: true)
        }
        let projected = TimelineChartLayout.bars(
            entries: entries,
            compression: compression,
            totalExtent: totalExtent
        )
        barLayouts[key] = projected
        return projected
    }
}

extension TimelineChart {
    var horizontalTimeline: some View {
        TimelineChartHorizontalLayout(model: model, revision: model.revision) {
            plot(.horizontal)
                .timelineChartLayoutRole(.plot)

            ForEach(model.gaps) { gap in
                omittedGapLabel(gap)
                    .timelineChartLayoutRole(.gapLabel(gap.id))
                    .zIndex(1)
            }

            axisLabels(.horizontal)
                .timelineChartLayoutRole(.axisLabels)
        }
    }

    var verticalTimeline: some View {
        let height = TimelineChartLayout.verticalTimelineHeight(
            minimumHeight: compactHeight,
            gapLabelCount: model.gaps.count
        )
        let gapLabelPlacements = TimelineChartLayout.verticalGapLabels(
            gaps: model.gaps,
            compression: model.compression,
            axisLength: TimelineChartLayout.axisLength(totalExtent: height)
        )

        return GeometryReader { viewport in
            ScrollView(.horizontal) {
                TimelineChartVerticalLayout(model: model, revision: model.revision) {
                    plot(.vertical)
                        .timelineChartLayoutRole(.plot)

                    axisLabels(.vertical)
                        .timelineChartLayoutRole(.axisLabels)

                    ForEach(gapLabelPlacements) { placement in
                        if let gap = model.gapByID[placement.id] {
                            omittedGapLabel(gap)
                                .timelineChartLayoutRole(.gapLabel(gap.id))
                                .zIndex(1)

                            // Both directions are supplied; the layout shows
                            // the one that matches the measured label position.
                            verticalGapConnector(descends: true)
                                .timelineChartLayoutRole(.gapConnector(gap.id, descends: true))
                            verticalGapConnector(descends: false)
                                .timelineChartLayoutRole(.gapConnector(gap.id, descends: false))
                        }
                    }
                }
                .frame(minWidth: viewport.size.width)
                .frame(height: viewport.size.height)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
        .frame(height: height)
    }

    /// Grid, gap markers, and bars. The bars are real views so each keeps
    /// its accessibility element; the bar layout places them from the memo.
    private func plot(_ axis: TimelineChartAxis) -> some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                drawGrid(axis, in: &context, size: size)
            }
            .accessibilityHidden(true)

            TimelineChartBarsLayout(model: model, axis: axis, revision: model.revision) {
                ForEach(model.entries) { entry in
                    bar(entry, axis: axis)
                        .layoutValue(key: TimelineChartBarIDKey.self, value: entry.id)
                }
            }
        }
    }

    private func axisLabels(_ axis: TimelineChartAxis) -> some View {
        Canvas { context, size in
            drawHourLabels(axis, in: &context, size: size)
        }
        .accessibilityHidden(true)
    }
}

private nonisolated enum TimelineChartLayoutSubviewRole: Hashable {
    case content
    case plot
    case axisLabels
    case gapLabel(String)
    case gapConnector(String, descends: Bool)
}

private nonisolated struct TimelineChartLayoutSubviewRoleKey: LayoutValueKey {
    static let defaultValue = TimelineChartLayoutSubviewRole.content
}

private nonisolated struct TimelineChartBarIDKey: LayoutValueKey {
    static let defaultValue: TimelineEntryID? = nil
}

private extension View {
    func timelineChartLayoutRole(
        _ role: TimelineChartLayoutSubviewRole
    ) -> some View {
        layoutValue(key: TimelineChartLayoutSubviewRoleKey.self, value: role)
    }
}

/// Places each bar at its projected time span and overlap lane.
private struct TimelineChartBarsLayout: Layout {
    let model: TimelineChartModel
    let axis: TimelineChartAxis
    let revision: Int

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews _: Subviews,
        cache _: inout ()
    ) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        let isHorizontal = axis == .horizontal
        let bars = model.bars(axis, totalExtent: isHorizontal ? bounds.width : bounds.height)
        let lanes = TimelineChartLayout.lanes(
            axis: axis,
            crossExtent: isHorizontal ? bounds.height : bounds.width,
            laneCount: bars.laneCount
        )
        for subview in subviews {
            guard let id = subview[TimelineChartBarIDKey.self],
                  let placement = bars.placementByID[id]
            else {
                continue
            }
            let laneOffset = lanes.offset(for: placement.lane)
            subview.place(
                at: CGPoint(
                    x: bounds.minX + (isHorizontal ? placement.axisOrigin : laneOffset),
                    y: bounds.minY + (isHorizontal ? laneOffset : placement.axisOrigin)
                ),
                anchor: .topLeading,
                proposal: ProposedViewSize(
                    width: isHorizontal ? placement.axisExtent : lanes.laneExtent,
                    height: isHorizontal ? lanes.laneExtent : placement.axisExtent
                )
            )
        }
    }
}

private struct TimelineChartHorizontalLayout: Layout {
    let model: TimelineChartModel
    let revision: Int

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) -> CGSize {
        guard subviews.isEmpty == false else { return .zero }
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 640
        return CGSize(width: width, height: metrics(width: width, subviews: subviews).totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        let metrics = metrics(width: bounds.width, subviews: subviews)

        for subview in subviews {
            switch subview[TimelineChartLayoutSubviewRoleKey.self] {
            case .plot:
                subview.place(
                    at: bounds.origin,
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: bounds.width, height: metrics.plotHeight)
                )
            case .axisLabels:
                subview.place(
                    at: CGPoint(
                        x: bounds.minX,
                        y: bounds.minY + metrics.plotHeight + metrics.gapAnnotationHeight
                    ),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(
                        width: bounds.width,
                        height: TimelineChartLayout.horizontalAxisLabelHeight
                    )
                )
            case let .gapLabel(id):
                guard let placement = metrics.placementByID[id],
                      let size = metrics.labelSizes[id]
                else {
                    continue
                }
                let rowOrigin = bounds.minY + metrics.plotHeight +
                    TimelineChartLayout.horizontalAnnotationSpacing +
                    CGFloat(placement.row) * (
                        metrics.labelHeight + TimelineChartLayout.horizontalGapLabelRowSpacing
                    )
                subview.place(
                    at: CGPoint(
                        x: bounds.minX + placement.axisOrigin + placement.axisExtent / 2,
                        y: rowOrigin + metrics.labelHeight / 2
                    ),
                    anchor: .center,
                    proposal: ProposedViewSize(size)
                )
            case .content, .gapConnector:
                continue
            }
        }
    }

    private func metrics(width: CGFloat, subviews: Subviews) -> Metrics {
        let labelSizes = measuredGapLabelSizes(in: subviews)
        let bars = model.bars(.horizontal, totalExtent: width)
        let gapLayout = TimelineChartLayout.horizontalGapLabels(
            gaps: model.gaps,
            compression: model.compression,
            axisLength: bars.axisLength,
            labelWidths: labelSizes.mapValues(\.width)
        )
        let labelHeight = labelSizes.values.map(\.height).max() ?? 0
        let plotHeight = TimelineChartLayout.horizontalPlotHeight(laneCount: bars.laneCount)
        let gapAnnotationHeight = TimelineChartLayout.horizontalGapAnnotationHeight(
            rowCount: gapLayout.rowCount,
            labelHeight: labelHeight
        )
        return Metrics(
            plotHeight: plotHeight,
            labelHeight: labelHeight,
            gapAnnotationHeight: gapAnnotationHeight,
            labelSizes: labelSizes,
            placementByID: Dictionary(
                gapLayout.placements.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        )
    }

    private struct Metrics {
        let plotHeight: CGFloat
        let labelHeight: CGFloat
        let gapAnnotationHeight: CGFloat
        let labelSizes: [String: CGSize]
        let placementByID: [String: TimelineChartHorizontalGapLabelPlacement]

        var totalHeight: CGFloat {
            plotHeight + gapAnnotationHeight + TimelineChartLayout.horizontalAxisLabelHeight
        }
    }
}

private struct TimelineChartVerticalLayout: Layout {
    let model: TimelineChartModel
    let revision: Int

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) -> CGSize {
        guard subviews.isEmpty == false else { return .zero }
        let height = proposal.height.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 360
        let metrics = metrics(proposedWidth: proposal.width, height: height, subviews: subviews)
        return CGSize(width: metrics.width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        let metrics = metrics(proposedWidth: bounds.width, height: bounds.height, subviews: subviews)

        for subview in subviews {
            switch subview[TimelineChartLayoutSubviewRoleKey.self] {
            case .plot:
                subview.place(
                    at: CGPoint(x: bounds.minX + metrics.axisLabelWidth, y: bounds.minY),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(
                        width: max(0, metrics.width - metrics.axisLabelWidth),
                        height: bounds.height
                    )
                )
            case .axisLabels:
                subview.place(
                    at: bounds.origin,
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: metrics.axisLabelWidth, height: bounds.height)
                )
            case let .gapLabel(id):
                guard let placement = metrics.placementByID[id],
                      let size = metrics.labelSizes[id]
                else {
                    continue
                }
                subview.place(
                    at: CGPoint(
                        x: bounds.minX + metrics.axisLabelWidth / 2,
                        y: bounds.minY + placement.axisOrigin + placement.axisExtent / 2
                    ),
                    anchor: .center,
                    proposal: ProposedViewSize(size)
                )
            case let .gapConnector(id, descends):
                guard let placement = metrics.placementByID[id],
                      let size = metrics.labelSizes[id]
                else {
                    continue
                }
                let labelTrailing = bounds.minX + (metrics.axisLabelWidth + size.width) / 2
                let labelMidY = bounds.minY + placement.axisOrigin + placement.axisExtent / 2
                let anchorY = bounds.minY + placement.anchorPosition
                guard descends == (anchorY >= labelMidY) else {
                    subview.place(at: bounds.origin, proposal: .zero)
                    continue
                }
                subview.place(
                    at: CGPoint(x: labelTrailing, y: min(labelMidY, anchorY)),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(
                        width: max(1, bounds.minX + metrics.axisLabelWidth - labelTrailing),
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
    ) -> Metrics {
        let bars = model.bars(.vertical, totalExtent: height)
        let labelSizes = measuredGapLabelSizes(in: subviews)
        let placements = TimelineChartLayout.verticalGapLabels(
            gaps: model.gaps,
            compression: model.compression,
            axisLength: bars.axisLength,
            labelHeight: max(
                TimelineChartLayout.verticalGapLabelHeight,
                labelSizes.values.map(\.height).max() ?? 0
            )
        )
        let axisLabelWidth = TimelineChartLayout.verticalAxisLabelWidth(
            for: labelSizes.values.map(\.width)
        )
        let minimumWidth = TimelineChartLayout.verticalMinimumContentWidth(
            laneCount: bars.laneCount,
            axisLabelWidth: axisLabelWidth
        )
        let proposed = proposedWidth.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 320
        return Metrics(
            width: max(minimumWidth, proposed),
            axisLabelWidth: axisLabelWidth,
            labelSizes: labelSizes,
            placementByID: Dictionary(
                placements.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        )
    }

    private struct Metrics {
        let width: CGFloat
        let axisLabelWidth: CGFloat
        let labelSizes: [String: CGSize]
        let placementByID: [String: TimelineChartVerticalGapLabelPlacement]
    }
}

private func measuredGapLabelSizes(
    in subviews: LayoutSubviews
) -> [String: CGSize] {
    subviews.reduce(into: [:]) { result, subview in
        guard case let .gapLabel(id) = subview[TimelineChartLayoutSubviewRoleKey.self] else {
            return
        }
        let measured = subview.sizeThatFits(.unspecified)
        result[id] = CGSize(
            width: measured.width.isFinite ? max(0, measured.width) : 0,
            height: measured.height.isFinite ? max(0, measured.height) : 0
        )
    }
}
