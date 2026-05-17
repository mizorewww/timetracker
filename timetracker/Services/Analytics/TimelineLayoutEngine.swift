import Foundation

enum TimelineLayoutEngine {
    static func layout(
        items: [TimelineLayoutItem],
        dayInterval: DateInterval,
        minimumLaneGap: TimeInterval = 60
    ) -> TimelineLayoutResult {
        PerformanceSignpost.interval("Timeline layout") {
            layoutWithoutInstrumentation(
                items: items,
                dayInterval: dayInterval,
                minimumLaneGap: minimumLaneGap
            )
        }
    }

    private static func layoutWithoutInstrumentation(
        items: [TimelineLayoutItem],
        dayInterval: DateInterval,
        minimumLaneGap: TimeInterval
    ) -> TimelineLayoutResult {
        let visibleItems = items
            .compactMap { clippedItem($0, to: dayInterval) }
            .sorted {
                if $0.startedAt == $1.startedAt {
                    return $0.endedAt < $1.endedAt
                }
                return $0.startedAt < $1.startedAt
            }

        let displayInterval = makeDisplayInterval(for: visibleItems, dayInterval: dayInterval)
        var laneEnds: [Date] = []
        var endingLanes = MinHeap<TimelineLaneAvailability> { lhs, rhs in
            if lhs.endedAt == rhs.endedAt {
                return lhs.lane < rhs.lane
            }
            return lhs.endedAt < rhs.endedAt
        }
        var availableLanes = MinHeap<Int>(sort: <)
        var entries: [TimelineLayoutEntry] = []

        for item in visibleItems {
            releaseAvailableLanes(
                startingAt: item.startedAt,
                laneEnds: laneEnds,
                minimumLaneGap: minimumLaneGap,
                endingLanes: &endingLanes,
                availableLanes: &availableLanes
            )
            let lane = availableLanes.popMin() ?? laneEnds.count

            if lane == laneEnds.count {
                laneEnds.append(item.endedAt)
            } else {
                laneEnds[lane] = item.endedAt
            }
            endingLanes.insert(TimelineLaneAvailability(lane: lane, endedAt: item.endedAt))

            entries.append(TimelineLayoutEntry(item: item, lane: lane))
        }

        return TimelineLayoutResult(displayInterval: displayInterval, entries: entries)
    }

    static func makeDisplayInterval(
        for items: [TimelineLayoutItem],
        dayInterval: DateInterval
    ) -> DateInterval {
        var earliestStart: Date?
        var latestEnd: Date?

        for item in items {
            earliestStart = earliestStart.map { min($0, item.startedAt) } ?? item.startedAt
            latestEnd = latestEnd.map { max($0, item.endedAt) } ?? item.endedAt
        }

        guard let earliestStart, let latestEnd else {
            return dayInterval
        }

        let start = max(earliestStart, dayInterval.start)
        let end = min(latestEnd, dayInterval.end)

        guard end > start else {
            return dayInterval
        }

        return DateInterval(start: start, end: end)
    }

    private static func releaseAvailableLanes(
        startingAt start: Date,
        laneEnds: [Date],
        minimumLaneGap: TimeInterval,
        endingLanes: inout MinHeap<TimelineLaneAvailability>,
        availableLanes: inout MinHeap<Int>
    ) {
        while let candidate = endingLanes.min {
            guard laneEnds.indices.contains(candidate.lane),
                  laneEnds[candidate.lane] == candidate.endedAt else {
                _ = endingLanes.popMin()
                continue
            }
            guard start.timeIntervalSince(candidate.endedAt) > minimumLaneGap else {
                return
            }
            _ = endingLanes.popMin()
            availableLanes.insert(candidate.lane)
        }
    }

    private static func clippedItem(
        _ item: TimelineLayoutItem,
        to dayInterval: DateInterval
    ) -> TimelineLayoutItem? {
        guard item.endedAt > dayInterval.start, item.startedAt < dayInterval.end else {
            return nil
        }

        let start = max(item.startedAt, dayInterval.start)
        let end = min(item.endedAt, dayInterval.end)
        guard end > start else { return nil }

        return TimelineLayoutItem(id: item.id, startedAt: start, endedAt: end)
    }
}
