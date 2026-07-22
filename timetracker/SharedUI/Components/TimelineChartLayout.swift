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

nonisolated enum TimelineChartLayout {
    static let verticalAxisLabelWidth: CGFloat = 96
    static let verticalTrailingInset: CGFloat = 12
    static let verticalMinimumBarExtent: CGFloat = 20
    static let verticalMinimumBarSpacing: CGFloat = 6
    static let verticalGapLabelHeight: CGFloat = 32

    static func horizontalLanes(
        height: CGFloat,
        laneCount: Int,
        axisLabelHeight: CGFloat = 24
    ) -> TimelineChartLaneLayout {
        centeredLanes(
            plotOrigin: 0,
            plotExtent: max(1, height - axisLabelHeight),
            laneCount: laneCount,
            preferredLaneExtent: 24,
            preferredSpacing: 10
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

    /// Projects compact vertical marks before assigning visual lanes.
    ///
    /// Reserving one minimum mark extent below the time axis means a terminal
    /// short event can stay anchored to its projected start and grow downward,
    /// instead of being shifted upward to fit inside the chart.
    static func verticalBars(
        entries: [AnalyticsTimelineEntry],
        compression: TimelineAxisCompression,
        height: CGFloat,
        minimumBarExtent: CGFloat = verticalMinimumBarExtent,
        minimumSpacing: CGFloat = verticalMinimumBarSpacing
    ) -> TimelineChartBarLayout {
        let totalHeight = finiteNonnegative(height)
        let markExtent = min(
            totalHeight,
            finiteNonnegative(minimumBarExtent)
        )
        let axisLength = max(0, totalHeight - markExtent)
        let spacing = finiteNonnegative(minimumSpacing)
        guard totalHeight > 0, entries.isEmpty == false else {
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
            let availableExtent = max(0, totalHeight - origin)
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

private nonisolated struct ProjectedBar {
    let origin: CGFloat
    let extent: CGFloat

    var end: CGFloat {
        origin + extent
    }
}
