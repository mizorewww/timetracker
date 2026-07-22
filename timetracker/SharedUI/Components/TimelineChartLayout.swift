import CoreGraphics
import Foundation
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
    var midpoint: CGFloat {
        origin + groupExtent / 2
    }
    func offset(for lane: Int) -> CGFloat {
        origin + CGFloat(max(0, lane)) * (laneExtent + laneSpacing)
    }
}

nonisolated struct TimelineChartBarPlacement: Identifiable, Equatable, Sendable {
    let id: TimelineEntryID
    let lane: Int
    let axisOrigin: CGFloat
    let axisExtent: CGFloat

    var axisEnd: CGFloat {
        axisOrigin + axisExtent
    }
}

nonisolated struct TimelineChartBarLayout: Equatable, Sendable {
    let axisLength: CGFloat
    let placements: [TimelineChartBarPlacement]
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

nonisolated enum TimelineChartLayout {
    static let horizontalMinimumBarExtent: CGFloat = 18
    static let horizontalMinimumBarSpacing: CGFloat = 6
    static let horizontalPreferredLaneExtent: CGFloat = 24
    static let horizontalPreferredLaneSpacing: CGFloat = 10
    static let horizontalAxisLabelHeight: CGFloat = 24
    static let horizontalGapLabelHeight: CGFloat = 32
    static let horizontalAnnotationSpacing: CGFloat = 4
    static let horizontalGapLabelWidth: CGFloat = 96
    static let horizontalGapLabelMinimumSpacing: CGFloat = 4
    static let horizontalGapLabelRowSpacing: CGFloat = 4
    static let verticalAxisLabelWidth: CGFloat = 96
    static let verticalTrailingInset: CGFloat = 12
    static let verticalMinimumBarExtent: CGFloat = 20
    static let verticalMinimumBarSpacing: CGFloat = 6
    static let verticalGapLabelHeight: CGFloat = 32

    static func horizontalLanes(
        height: CGFloat,
        laneCount: Int,
        gapLabelRowCount: Int
    ) -> TimelineChartLaneLayout {
        centeredLanes(
            plotOrigin: 0,
            plotExtent: max(
                1,
                height - horizontalAnnotationHeight(
                    gapLabelRowCount: gapLabelRowCount
                )
            ),
            laneCount: laneCount,
            preferredLaneExtent: horizontalPreferredLaneExtent,
            preferredSpacing: horizontalPreferredLaneSpacing
        )
    }
    static func verticalLanes(
        width: CGFloat,
        laneCount: Int,
        axisLabelWidth: CGFloat = verticalAxisLabelWidth,
        trailingInset: CGFloat = verticalTrailingInset
    ) -> TimelineChartLaneLayout {
        let safeWidth = max(1, width)
        let plotOrigin = min(axisLabelWidth, max(0, safeWidth - trailingInset))
        return centeredLanes(
            plotOrigin: plotOrigin,
            plotExtent: max(1, safeWidth - plotOrigin - trailingInset),
            laneCount: laneCount,
            preferredLaneExtent: 38,
            preferredSpacing: 8
        )
    }

    static func horizontalGapAnnotationHeight(rowCount: Int) -> CGFloat {
        let count = max(0, rowCount)
        guard count > 0 else { return 0 }
        return horizontalAnnotationSpacing +
            CGFloat(count) * horizontalGapLabelHeight +
            CGFloat(count - 1) * horizontalGapLabelRowSpacing
    }

    static func horizontalAnnotationHeight(gapLabelRowCount: Int) -> CGFloat {
        horizontalGapAnnotationHeight(rowCount: gapLabelRowCount) +
            horizontalAxisLabelHeight
    }

    static func horizontalPlotHeight(
        height: CGFloat,
        gapLabelRowCount: Int
    ) -> CGFloat {
        max(
            0,
            finiteNonnegative(height) - horizontalAnnotationHeight(
                gapLabelRowCount: gapLabelRowCount
            )
        )
    }

    static func horizontalAxisLabelOrigin(
        plotHeight: CGFloat,
        gapLabelRowCount: Int
    ) -> CGFloat {
        finiteNonnegative(plotHeight) + horizontalGapAnnotationHeight(
            rowCount: gapLabelRowCount
        )
    }

    static func horizontalTimelineHeight(
        laneCount: Int,
        gapLabelRowCount: Int
    ) -> CGFloat {
        let count = max(1, laneCount)
        let groupExtent =
            CGFloat(count) * horizontalPreferredLaneExtent +
            CGFloat(max(0, count - 1)) * horizontalPreferredLaneSpacing
        return max(
            120,
            groupExtent + 20 + horizontalAnnotationHeight(
                gapLabelRowCount: gapLabelRowCount
            )
        )
    }

    /// Projects horizontal marks before assigning visual lanes. Reserving one
    /// minimum mark extent after the time axis lets a terminal short event stay
    /// anchored to its projected start and grow rightward without clipping.
    static func horizontalBars(
        entries: [AnalyticsTimelineEntry],
        compression: TimelineAxisCompression,
        width: CGFloat,
        minimumBarExtent: CGFloat = horizontalMinimumBarExtent,
        minimumSpacing: CGFloat = horizontalMinimumBarSpacing
    ) -> TimelineChartBarLayout {
        projectedBars(
            entries: entries,
            compression: compression,
            totalAxisExtent: width,
            minimumBarExtent: minimumBarExtent,
            minimumSpacing: minimumSpacing
        )
    }

    /// Projects compact vertical marks before assigning visual lanes.
    /// Reserving one minimum mark extent below the time axis lets a terminal
    /// short event stay anchored to its projected start and grow downward.
    static func verticalBars(
        entries: [AnalyticsTimelineEntry],
        compression: TimelineAxisCompression,
        height: CGFloat,
        minimumBarExtent: CGFloat = verticalMinimumBarExtent,
        minimumSpacing: CGFloat = verticalMinimumBarSpacing
    ) -> TimelineChartBarLayout {
        projectedBars(
            entries: entries,
            compression: compression,
            totalAxisExtent: height,
            minimumBarExtent: minimumBarExtent,
            minimumSpacing: minimumSpacing
        )
    }

    static func horizontalGapLabels(
        gaps: [TimelineOmittedGap],
        compression: TimelineAxisCompression,
        axisLength: CGFloat,
        labelWidth: CGFloat = horizontalGapLabelWidth,
        minimumSpacing: CGFloat = horizontalGapLabelMinimumSpacing
    ) -> TimelineChartHorizontalGapLabelLayout {
        let length = finiteNonnegative(axisLength)
        let width = min(finiteNonnegative(labelWidth), length)
        guard width > 0, gaps.isEmpty == false else {
            return TimelineChartHorizontalGapLabelLayout(
                placements: [],
                rowCount: 0
            )
        }
        let spacing = finiteNonnegative(minimumSpacing)
        let candidates = gaps.map { gap in
            let rawPosition = length * CGFloat(
                compression.ratio(
                    forCompressedOffset: gap.compressedMidpointOffset
                )
            )
            let position = rawPosition.isFinite ? rawPosition : 0
            let origin = min(
                max(0, position - width / 2),
                max(0, length - width)
            )
            return HorizontalGapLabelCandidate(
                id: gap.id,
                origin: origin,
                extent: width
            )
        }
        .sorted {
            if $0.origin != $1.origin {
                return $0.origin < $1.origin
            }
            if $0.end != $1.end {
                return $0.end < $1.end
            }
            return $0.id < $1.id
        }

        var rowEnds: [CGFloat] = []
        var placements: [TimelineChartHorizontalGapLabelPlacement] = []
        placements.reserveCapacity(candidates.count)

        for candidate in candidates {
            let row = rowEnds.firstIndex { rowEnd in
                candidate.origin - rowEnd >= spacing
            } ?? rowEnds.count
            if row == rowEnds.count {
                rowEnds.append(candidate.end)
            } else {
                rowEnds[row] = candidate.end
            }
            placements.append(
                TimelineChartHorizontalGapLabelPlacement(
                    id: candidate.id,
                    row: row,
                    axisOrigin: candidate.origin,
                    axisExtent: candidate.extent
                )
            )
        }

        return TimelineChartHorizontalGapLabelLayout(
            placements: placements,
            rowCount: rowEnds.count
        )
    }

    static func horizontalGapLabelFrame(
        placement: TimelineChartHorizontalGapLabelPlacement,
        plotHeight: CGFloat,
        labelHeight: CGFloat = horizontalGapLabelHeight,
        rowSpacing: CGFloat = horizontalGapLabelRowSpacing
    ) -> CGRect {
        let row = max(0, placement.row)
        let height = finiteNonnegative(labelHeight)
        let spacing = finiteNonnegative(rowSpacing)

        return CGRect(
            x: finiteNonnegative(placement.axisOrigin),
            y: finiteNonnegative(plotHeight) +
                horizontalAnnotationSpacing +
                CGFloat(row) * (height + spacing),
            width: finiteNonnegative(placement.axisExtent),
            height: height
        )
    }

    static func verticalGapLabelFrame(
        position: CGFloat,
        axisLength: CGFloat,
        axisLabelWidth: CGFloat = verticalAxisLabelWidth,
        labelHeight: CGFloat = verticalGapLabelHeight,
        horizontalInset: CGFloat = 6
    ) -> CGRect {
        let length = finiteNonnegative(axisLength)
        let gutterWidth = finiteNonnegative(axisLabelWidth)
        let inset = min(finiteNonnegative(horizontalInset), gutterWidth / 2)
        let height = min(finiteNonnegative(labelHeight), length)
        let coordinate = position.isFinite ? position : 0
        let originY = min(
            max(0, coordinate - height / 2),
            max(0, length - height)
        )

        return CGRect(
            x: inset,
            y: originY,
            width: max(0, gutterWidth - 2 * inset),
            height: height
        )
    }

    static func verticalAxisTicks(
        displayInterval: DateInterval,
        compression: TimelineAxisCompression,
        axisLength: CGFloat,
        minimumSpacing: CGFloat,
        calendar: Calendar = .current,
        tickLabelHeight: CGFloat = 16,
        collisionClearance: CGFloat = 2
    ) -> [TimelineChartAxisTick] {
        let length = finiteNonnegative(axisLength)
        let labelHeight = min(finiteNonnegative(tickLabelHeight), length)
        let clearance = finiteNonnegative(collisionClearance)
        let gapFrames = compression.omittedGaps.map { gap in
            verticalGapLabelFrame(
                position: length * CGFloat(
                    compression.ratio(
                        forCompressedOffset: gap.compressedMidpointOffset
                    )
                ),
                axisLength: length
            )
        }

        return axisTicks(
            displayInterval: displayInterval,
            compression: compression,
            axisLength: length,
            minimumSpacing: minimumSpacing,
            calendar: calendar
        )
        .filter { tick in
            guard tick.role == .interior else { return true }
            let position = length * CGFloat(compression.ratio(for: tick.date))
            let tickFrame = CGRect(
                x: 0,
                y: axisLabelOrigin(
                    position: position,
                    axisLength: length,
                    labelExtent: labelHeight,
                    role: tick.role
                ) - clearance,
                width: verticalAxisLabelWidth,
                height: labelHeight + 2 * clearance
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
        let start = TimelineChartAxisTick(
            date: displayInterval.start,
            role: .start
        )
        guard displayInterval.end > displayInterval.start else {
            return [start]
        }
        let length = max(0, axisLength)
        let spacing = max(0, minimumSpacing)
        let endPosition = length * CGFloat(
            compression.ratio(for: displayInterval.end)
        )
        var ticks = [start]
        var lastPosition: CGFloat = 0
        for date in interiorHourTicks(
            in: displayInterval,
            calendar: calendar
        ) where !compression.isInsideOmittedGap(date) {
            let position = length * CGFloat(compression.ratio(for: date))
            guard position - lastPosition >= spacing,
                  endPosition - position >= spacing else {
                continue
            }
            ticks.append(TimelineChartAxisTick(date: date, role: .interior))
            lastPosition = position
        }
        ticks.append(
            TimelineChartAxisTick(date: displayInterval.end, role: .end)
        )
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
        plotOrigin: CGFloat,
        plotExtent: CGFloat,
        laneCount: Int,
        preferredLaneExtent: CGFloat,
        preferredSpacing: CGFloat
    ) -> TimelineChartLaneLayout {
        let count = max(1, laneCount)
        let available = max(1, plotExtent)
        let gapCount = max(0, count - 1)
        let spacing: CGFloat
        if gapCount == 0 {
            spacing = 0
        } else {
            spacing = min(
                preferredSpacing,
                max(0, (available - CGFloat(count)) / CGFloat(gapCount))
            )
        }
        let laneExtent = max(
            1,
            min(
                preferredLaneExtent,
                (available - spacing * CGFloat(gapCount)) / CGFloat(count)
            )
        )
        let groupExtent =
            laneExtent * CGFloat(count) + spacing * CGFloat(gapCount)
        let origin = plotOrigin + max(0, (available - groupExtent) / 2)

        return TimelineChartLaneLayout(
            origin: origin,
            laneExtent: laneExtent,
            laneSpacing: spacing,
            groupExtent: groupExtent
        )
    }

    private static func projectedBars(
        entries: [AnalyticsTimelineEntry],
        compression: TimelineAxisCompression,
        totalAxisExtent: CGFloat,
        minimumBarExtent: CGFloat,
        minimumSpacing: CGFloat
    ) -> TimelineChartBarLayout {
        let totalExtent = finiteNonnegative(totalAxisExtent)
        let markExtent = min(
            totalExtent,
            finiteNonnegative(minimumBarExtent)
        )
        let axisLength = max(0, totalExtent - markExtent)
        let spacing = finiteNonnegative(minimumSpacing)
        guard totalExtent > 0, entries.isEmpty == false else {
            return TimelineChartBarLayout(
                axisLength: axisLength,
                placements: [],
                laneCount: 0
            )
        }

        var projectedByID: [TimelineEntryID: ProjectedBar] = [:]
        var intervals: [TimelineLaneInterval] = []
        projectedByID.reserveCapacity(entries.count)
        intervals.reserveCapacity(entries.count)

        for entry in entries where projectedByID[entry.id] == nil {
            let origin = projectedPosition(
                for: entry.interval.start,
                compression: compression,
                axisLength: axisLength
            )
            let naturalEnd = max(
                origin,
                projectedPosition(
                    for: entry.interval.end,
                    compression: compression,
                    axisLength: axisLength
                )
            )
            let availableExtent = max(0, totalExtent - origin)
            let extent = min(
                availableExtent,
                max(markExtent, naturalEnd - origin)
            )
            let projected = ProjectedBar(origin: origin, extent: extent)
            projectedByID[entry.id] = projected
            intervals.append(
                TimelineLaneInterval(
                    id: entry.id,
                    start: Double(origin),
                    end: Double(projected.end)
                )
            )
        }

        let assignments = TimelineLaneAllocator.assignments(
            for: intervals,
            minimumGap: Double(spacing),
            allowsReuseAtMinimumGap: true
        )
        let placements = assignments.compactMap { assignment in
            projectedByID[assignment.id].map { projected in
                TimelineChartBarPlacement(
                    id: assignment.id,
                    lane: assignment.lane,
                    axisOrigin: projected.origin,
                    axisExtent: projected.extent
                )
            }
        }

        return TimelineChartBarLayout(
            axisLength: axisLength,
            placements: placements,
            laneCount: (placements.map(\.lane).max() ?? -1) + 1
        )
    }

    private static func projectedPosition(
        for date: Date,
        compression: TimelineAxisCompression,
        axisLength: CGFloat
    ) -> CGFloat {
        let rawRatio = compression.ratio(for: date)
        let ratio = rawRatio.isFinite ? min(max(0, rawRatio), 1) : 0
        return axisLength * CGFloat(ratio)
    }

    private static func finiteNonnegative(_ value: CGFloat) -> CGFloat {
        value.isFinite ? max(0, value) : 0
    }

    private static func interiorHourTicks(
        in interval: DateInterval,
        calendar: Calendar
    ) -> [Date] {
        let totalHours = max(1, interval.duration / 3_600)
        let step = totalHours <= 4 ? 1 : (totalHours <= 10 ? 2 : 4)
        var tick = calendar.dateInterval(
            of: .hour,
            for: interval.start
        )?.start ?? interval.start
        var result: [Date] = []

        while let next = calendar.date(
            byAdding: .hour,
            value: step,
            to: tick
        ) {
            tick = next
            guard tick < interval.end else { break }
            if tick > interval.start {
                result.append(tick)
            }
        }
        return result
    }
}

private nonisolated struct HorizontalGapLabelCandidate {
    let id: String
    let origin: CGFloat
    let extent: CGFloat

    var end: CGFloat {
        origin + extent
    }
}

private nonisolated struct ProjectedBar {
    let origin: CGFloat
    let extent: CGFloat

    var end: CGFloat {
        origin + extent
    }
}
