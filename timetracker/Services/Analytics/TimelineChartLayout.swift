import CoreGraphics
import Foundation

/// Direction time runs on a timeline chart.
nonisolated enum TimelineChartAxis: Hashable, Sendable {
    case horizontal
    case vertical
}

nonisolated enum TimelineChartAxisTickRole: Equatable, Sendable {
    case start
    case interior
    case end
    var isBoundary: Bool {
        self != .interior
    }
}

nonisolated struct TimelineChartAxisTick: Equatable, Sendable {
    let date: Date
    let role: TimelineChartAxisTickRole
}

nonisolated struct TimelineChartLaneLayout: Equatable, Sendable {
    let origin: CGFloat
    let laneExtent: CGFloat
    let laneSpacing: CGFloat
    let groupExtent: CGFloat

    func offset(for lane: Int) -> CGFloat {
        origin + CGFloat(max(0, lane)) * (laneExtent + laneSpacing)
    }
}

nonisolated struct TimelineChartBarPlacement: Identifiable, Equatable, Sendable {
    let id: TimelineEntryID
    let lane: Int
    let axisOrigin: CGFloat
    let axisExtent: CGFloat
}

nonisolated struct TimelineChartBarLayout: Equatable, Sendable {
    let axisLength: CGFloat
    let placementByID: [TimelineEntryID: TimelineChartBarPlacement]
    let laneCount: Int
}

nonisolated struct TimelineChartHorizontalGapLabelPlacement: Identifiable, Equatable, Sendable {
    let id: String
    let row: Int
    let axisOrigin: CGFloat
    let axisExtent: CGFloat
}

nonisolated struct TimelineChartHorizontalGapLabelLayout: Equatable, Sendable {
    let placements: [TimelineChartHorizontalGapLabelPlacement]
    let rowCount: Int
}

nonisolated struct TimelineChartVerticalGapLabelPlacement: Identifiable, Equatable, Sendable {
    let id: String
    let anchorPosition: CGFloat
    let axisOrigin: CGFloat
    let axisExtent: CGFloat
}

nonisolated enum TimelineChartLayout {
    static let barIconExtent: CGFloat = 12
    static let barIconPadding: CGFloat = 4
    /// Shortest mark along the time axis and narrowest lane across it: room
    /// for the bar's icon plus padding.
    static let minimumBarFootprint = barIconExtent + 2 * barIconPadding
    static let minimumBarSpacing: CGFloat = 6
    static let horizontalPreferredLaneExtent: CGFloat = 24
    static let horizontalPreferredLaneSpacing: CGFloat = 10
    static let horizontalAxisLabelHeight: CGFloat = 24
    static let horizontalAnnotationSpacing: CGFloat = 4
    static let horizontalGapLabelMinimumSpacing: CGFloat = 4
    static let horizontalGapLabelRowSpacing: CGFloat = 4
    static let verticalAxisLabelWidth: CGFloat = 96
    static let verticalGapLabelHorizontalInset: CGFloat = 6
    static let verticalTrailingInset: CGFloat = 12
    static let verticalPreferredLaneExtent: CGFloat = 38
    static let verticalPreferredLaneSpacing: CGFloat = 8
    static let verticalGapLabelHeight: CGFloat = 32
    static let verticalGapLabelMinimumSpacing: CGFloat = 4
    static let verticalGapLabelBoundaryInset: CGFloat = 18

    /// Time-axis length inside `totalExtent`. One minimum mark extent stays
    /// reserved after the axis so a terminal short event keeps its projected
    /// start and grows forward without clipping.
    static func axisLength(totalExtent: CGFloat) -> CGFloat {
        max(0, totalExtent - minimumBarFootprint)
    }

    /// Lanes across the plot for `laneCount` overlapping marks, centered in
    /// `crossExtent` (plot height for a horizontal axis, width for vertical).
    static func lanes(
        axis: TimelineChartAxis,
        crossExtent: CGFloat,
        laneCount: Int
    ) -> TimelineChartLaneLayout {
        switch axis {
        case .horizontal:
            centeredLanes(
                plotExtent: crossExtent,
                laneCount: laneCount,
                preferredLaneExtent: horizontalPreferredLaneExtent,
                preferredSpacing: horizontalPreferredLaneSpacing
            )
        case .vertical:
            centeredLanes(
                plotExtent: crossExtent - verticalTrailingInset,
                laneCount: laneCount,
                preferredLaneExtent: verticalPreferredLaneExtent,
                preferredSpacing: verticalPreferredLaneSpacing
            )
        }
    }

    static func verticalMinimumContentWidth(
        laneCount: Int,
        axisLabelWidth: CGFloat
    ) -> CGFloat {
        let count = max(1, laneCount)
        return axisLabelWidth + verticalTrailingInset +
            CGFloat(count) * minimumBarFootprint +
            CGFloat(count - 1) * verticalPreferredLaneSpacing
    }

    static func verticalAxisLabelWidth(for gapLabelWidths: [CGFloat]) -> CGFloat {
        max(
            verticalAxisLabelWidth,
            (gapLabelWidths.max() ?? 0) + 2 * verticalGapLabelHorizontalInset
        )
    }

    static func horizontalGapAnnotationHeight(
        rowCount: Int,
        labelHeight: CGFloat
    ) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        return horizontalAnnotationSpacing +
            CGFloat(rowCount) * labelHeight +
            CGFloat(rowCount - 1) * horizontalGapLabelRowSpacing
    }

    static func horizontalPlotHeight(laneCount: Int) -> CGFloat {
        let count = max(1, laneCount)
        let groupExtent =
            CGFloat(count) * horizontalPreferredLaneExtent +
            CGFloat(count - 1) * horizontalPreferredLaneSpacing
        return max(120 - horizontalAxisLabelHeight, groupExtent + 20)
    }

    static func verticalTimelineHeight(
        minimumHeight: CGFloat,
        gapLabelCount: Int
    ) -> CGFloat {
        guard gapLabelCount > 0 else { return minimumHeight }
        let labelFootprint =
            2 * verticalGapLabelBoundaryInset +
            CGFloat(gapLabelCount) * verticalGapLabelHeight +
            CGFloat(gapLabelCount - 1) * verticalGapLabelMinimumSpacing
        return max(minimumHeight, minimumBarFootprint + labelFootprint)
    }

    /// Projects marks onto a time axis of `totalExtent` points (either
    /// direction) before assigning visual lanes.
    static func bars(
        entries: [AnalyticsTimelineEntry],
        compression: TimelineAxisCompression,
        totalExtent: CGFloat
    ) -> TimelineChartBarLayout {
        let totalExtent = max(0, totalExtent)
        let markExtent = min(totalExtent, minimumBarFootprint)
        let axisLength = axisLength(totalExtent: totalExtent)
        guard totalExtent > 0, entries.isEmpty == false else {
            return TimelineChartBarLayout(
                axisLength: axisLength,
                placementByID: [:],
                laneCount: 0
            )
        }

        var projectedByID: [TimelineEntryID: (origin: CGFloat, extent: CGFloat)] = [:]
        var intervals: [TimelineLaneInterval] = []
        projectedByID.reserveCapacity(entries.count)
        intervals.reserveCapacity(entries.count)

        for entry in entries where projectedByID[entry.id] == nil {
            let origin = position(of: entry.interval.start, compression: compression, axisLength: axisLength)
            let naturalEnd = max(
                origin,
                position(of: entry.interval.end, compression: compression, axisLength: axisLength)
            )
            let extent = min(
                max(0, totalExtent - origin),
                max(markExtent, naturalEnd - origin)
            )
            projectedByID[entry.id] = (origin, extent)
            intervals.append(
                TimelineLaneInterval(
                    id: entry.id,
                    start: Double(origin),
                    end: Double(origin + extent)
                )
            )
        }

        let assignments = TimelineLaneAllocator.assignments(
            for: intervals,
            minimumGap: Double(minimumBarSpacing),
            allowsReuseAtMinimumGap: true
        )
        var placementByID: [TimelineEntryID: TimelineChartBarPlacement] = [:]
        placementByID.reserveCapacity(assignments.count)
        var laneCount = 0
        for assignment in assignments {
            guard let projected = projectedByID[assignment.id] else { continue }
            placementByID[assignment.id] = TimelineChartBarPlacement(
                id: assignment.id,
                lane: assignment.lane,
                axisOrigin: projected.origin,
                axisExtent: projected.extent
            )
            laneCount = max(laneCount, assignment.lane + 1)
        }

        return TimelineChartBarLayout(
            axisLength: axisLength,
            placementByID: placementByID,
            laneCount: laneCount
        )
    }

    static func horizontalGapLabels(
        gaps: [TimelineOmittedGap],
        compression: TimelineAxisCompression,
        axisLength: CGFloat,
        labelWidths: [String: CGFloat]
    ) -> TimelineChartHorizontalGapLabelLayout {
        guard axisLength > 0, gaps.isEmpty == false else {
            return TimelineChartHorizontalGapLabelLayout(placements: [], rowCount: 0)
        }
        let candidates = gaps.compactMap { gap -> TimelineChartHorizontalGapLabelPlacement? in
            let width = labelWidths[gap.id] ?? 0
            guard width > 0 else { return nil }
            let position = axisLength * CGFloat(
                compression.ratio(forCompressedOffset: gap.compressedMidpointOffset)
            )
            return TimelineChartHorizontalGapLabelPlacement(
                id: gap.id,
                row: 0,
                axisOrigin: min(max(0, position - width / 2), max(0, axisLength - width)),
                axisExtent: width
            )
        }
        .sorted {
            if $0.axisOrigin != $1.axisOrigin {
                return $0.axisOrigin < $1.axisOrigin
            }
            if $0.axisExtent != $1.axisExtent {
                return $0.axisExtent < $1.axisExtent
            }
            return $0.id < $1.id
        }

        var rowEnds: [CGFloat] = []
        let placements = candidates.map { candidate in
            let end = candidate.axisOrigin + candidate.axisExtent
            let row = rowEnds.firstIndex { rowEnd in
                candidate.axisOrigin - rowEnd >= horizontalGapLabelMinimumSpacing
            } ?? rowEnds.count
            if row == rowEnds.count {
                rowEnds.append(end)
            } else {
                rowEnds[row] = end
            }
            return TimelineChartHorizontalGapLabelPlacement(
                id: candidate.id,
                row: row,
                axisOrigin: candidate.axisOrigin,
                axisExtent: candidate.axisExtent
            )
        }

        return TimelineChartHorizontalGapLabelLayout(
            placements: placements,
            rowCount: rowEnds.count
        )
    }

    /// Stacks omitted-gap labels in the vertical axis gutter near their gaps,
    /// dropping evenly spaced labels when the axis cannot fit them all.
    static func verticalGapLabels(
        gaps: [TimelineOmittedGap],
        compression: TimelineAxisCompression,
        axisLength: CGFloat,
        labelHeight: CGFloat = verticalGapLabelHeight
    ) -> [TimelineChartVerticalGapLabelPlacement] {
        let spacing = verticalGapLabelMinimumSpacing
        let inset = min(verticalGapLabelBoundaryInset, axisLength / 2)
        let availableStart = inset
        let availableEnd = max(availableStart, axisLength - inset)
        let availableExtent = availableEnd - availableStart

        guard gaps.isEmpty == false,
              labelHeight > 0,
              availableExtent >= labelHeight
        else {
            return []
        }

        let candidates = gaps.map { gap in
            let position = min(
                max(0, axisLength * CGFloat(
                    compression.ratio(forCompressedOffset: gap.compressedMidpointOffset)
                )),
                axisLength
            )
            return TimelineChartVerticalGapLabelPlacement(
                id: gap.id,
                anchorPosition: position,
                axisOrigin: min(
                    max(availableStart, position - labelHeight / 2),
                    availableEnd - labelHeight
                ),
                axisExtent: labelHeight
            )
        }
        .sorted {
            if $0.axisOrigin != $1.axisOrigin {
                return $0.axisOrigin < $1.axisOrigin
            }
            if $0.anchorPosition != $1.anchorPosition {
                return $0.anchorPosition < $1.anchorPosition
            }
            return $0.id < $1.id
        }

        let capacity = max(
            1,
            Int(floor((availableExtent + spacing) / (labelHeight + spacing)))
        )
        let visibleCandidates = evenlySpaced(candidates, maximumCount: capacity)
        var placements: [TimelineChartVerticalGapLabelPlacement] = []
        placements.reserveCapacity(visibleCandidates.count)

        for (index, candidate) in visibleCandidates.enumerated() {
            let lowerBound = placements.last.map {
                $0.axisOrigin + $0.axisExtent + spacing
            } ?? availableStart
            let remainingCount = visibleCandidates.count - index - 1
            let upperBound = availableEnd - labelHeight -
                CGFloat(remainingCount) * (labelHeight + spacing)
            placements.append(
                TimelineChartVerticalGapLabelPlacement(
                    id: candidate.id,
                    anchorPosition: candidate.anchorPosition,
                    axisOrigin: min(
                        max(candidate.axisOrigin, lowerBound),
                        max(lowerBound, upperBound)
                    ),
                    axisExtent: labelHeight
                )
            )
        }
        return placements
    }

    /// Hour ticks for a vertical axis, without interior ticks whose labels
    /// would collide with an omitted-gap label in the same gutter.
    static func verticalAxisTicks(
        displayInterval: DateInterval,
        compression: TimelineAxisCompression,
        axisLength: CGFloat,
        minimumSpacing: CGFloat,
        calendar: Calendar = .current,
        tickLabelHeight: CGFloat = 16,
        collisionClearance: CGFloat = 2,
        axisLabelWidth: CGFloat = verticalAxisLabelWidth,
        gapLabelHeight: CGFloat = verticalGapLabelHeight
    ) -> [TimelineChartAxisTick] {
        let labelHeight = min(tickLabelHeight, axisLength)
        let inset = min(verticalGapLabelHorizontalInset, axisLabelWidth / 2)
        let gapFrames = verticalGapLabels(
            gaps: compression.omittedGaps,
            compression: compression,
            axisLength: axisLength,
            labelHeight: gapLabelHeight
        ).map { placement in
            CGRect(
                x: inset,
                y: placement.axisOrigin,
                width: max(0, axisLabelWidth - 2 * inset),
                height: placement.axisExtent
            )
        }

        return axisTicks(
            displayInterval: displayInterval,
            compression: compression,
            axisLength: axisLength,
            minimumSpacing: minimumSpacing,
            calendar: calendar
        )
        .filter { tick in
            guard tick.role == .interior else { return true }
            let position = axisLength * CGFloat(compression.ratio(for: tick.date))
            let tickFrame = CGRect(
                x: 0,
                y: axisLabelOrigin(
                    position: position,
                    axisLength: axisLength,
                    labelExtent: labelHeight,
                    role: tick.role
                ) - collisionClearance,
                width: axisLabelWidth,
                height: labelHeight + 2 * collisionClearance
            )
            return gapFrames.contains { $0.intersects(tickFrame) } == false
        }
    }

    static func axisTicks(
        displayInterval: DateInterval,
        compression: TimelineAxisCompression,
        axisLength: CGFloat,
        minimumSpacing: CGFloat,
        calendar: Calendar = .current
    ) -> [TimelineChartAxisTick] {
        let start = TimelineChartAxisTick(date: displayInterval.start, role: .start)
        guard displayInterval.end > displayInterval.start else {
            return [start]
        }
        let length = max(0, axisLength)
        let endPosition = length * CGFloat(compression.ratio(for: displayInterval.end))
        var ticks = [start]
        var lastPosition: CGFloat = 0
        for date in interiorHourTicks(in: displayInterval, calendar: calendar)
            where !compression.isInsideOmittedGap(date)
        {
            let position = length * CGFloat(compression.ratio(for: date))
            guard position - lastPosition >= minimumSpacing,
                  endPosition - position >= minimumSpacing
            else {
                continue
            }
            ticks.append(TimelineChartAxisTick(date: date, role: .interior))
            lastPosition = position
        }
        ticks.append(TimelineChartAxisTick(date: displayInterval.end, role: .end))
        return ticks
    }

    static func axisLabelOrigin(
        position: CGFloat,
        axisLength: CGFloat,
        labelExtent: CGFloat,
        role: TimelineChartAxisTickRole
    ) -> CGFloat {
        let length = max(0, axisLength)
        let extent = min(max(0, labelExtent), length)
        let maximumOrigin = max(0, length - extent)
        switch role {
        case .start:
            return 0
        case .interior:
            return min(max(0, position - extent / 2), maximumOrigin)
        case .end:
            return maximumOrigin
        }
    }

    private static func centeredLanes(
        plotExtent: CGFloat,
        laneCount: Int,
        preferredLaneExtent: CGFloat,
        preferredSpacing: CGFloat
    ) -> TimelineChartLaneLayout {
        let count = max(1, laneCount)
        let available = max(1, plotExtent)
        let gapCount = count - 1
        let spacing: CGFloat = gapCount == 0
            ? 0
            : min(preferredSpacing, max(0, (available - CGFloat(count)) / CGFloat(gapCount)))
        let laneExtent = max(
            1,
            min(preferredLaneExtent, (available - spacing * CGFloat(gapCount)) / CGFloat(count))
        )
        let groupExtent = laneExtent * CGFloat(count) + spacing * CGFloat(gapCount)
        return TimelineChartLaneLayout(
            origin: max(0, (available - groupExtent) / 2),
            laneExtent: laneExtent,
            laneSpacing: spacing,
            groupExtent: groupExtent
        )
    }

    private static func position(
        of date: Date,
        compression: TimelineAxisCompression,
        axisLength: CGFloat
    ) -> CGFloat {
        axisLength * CGFloat(min(max(0, compression.ratio(for: date)), 1))
    }

    private static func evenlySpaced<Element>(
        _ candidates: [Element],
        maximumCount count: Int
    ) -> [Element] {
        guard count > 0, candidates.isEmpty == false else { return [] }
        guard candidates.count > count else { return candidates }
        guard count > 1 else { return [candidates[(candidates.count - 1) / 2]] }

        let lastIndex = candidates.count - 1
        return (0 ..< count).map { index in
            candidates[Int((Double(index) * Double(lastIndex) / Double(count - 1)).rounded())]
        }
    }

    private static func interiorHourTicks(
        in interval: DateInterval,
        calendar: Calendar
    ) -> [Date] {
        let totalHours = max(1, interval.duration / 3600)
        let step = totalHours <= 4 ? 1 : (totalHours <= 10 ? 2 : 4)
        var tick = calendar.dateInterval(of: .hour, for: interval.start)?.start ?? interval.start
        var result: [Date] = []

        while let next = calendar.date(byAdding: .hour, value: step, to: tick) {
            tick = next
            guard tick < interval.end else { break }
            if tick > interval.start {
                result.append(tick)
            }
        }
        return result
    }
}
