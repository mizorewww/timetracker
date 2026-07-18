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
nonisolated enum TimelineChartLayout {
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
        axisLabelWidth: CGFloat = 68,
        trailingInset: CGFloat = 12
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
