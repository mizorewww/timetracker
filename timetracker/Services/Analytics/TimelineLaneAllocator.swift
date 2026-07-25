import Foundation
import HeapModule

nonisolated struct TimelineLaneInterval: Equatable, Sendable {
    let id: TimelineEntryID
    let start: Double
    let end: Double
}

nonisolated struct TimelineLaneAssignment: Identifiable, Equatable, Sendable {
    let id: TimelineEntryID
    let lane: Int
}

/// Assigns a stable minimum set of lanes to sorted interval footprints.
///
/// Inputs can represent time or projected points. Keeping that distinction at
/// the call site lets domain snapshots stay device-independent while compact
/// charts account for their actual rendered mark size.
nonisolated enum TimelineLaneAllocator {
    static func assignments(
        for intervals: [TimelineLaneInterval],
        minimumGap: Double,
        allowsReuseAtMinimumGap: Bool = false
    ) -> [TimelineLaneAssignment] {
        let gap = minimumGap.isFinite ? max(0, minimumGap) : 0
        let sorted = intervals
            .filter { interval in
                interval.start.isFinite &&
                    interval.end.isFinite &&
                    interval.end >= interval.start
            }
            .sorted {
                if $0.start != $1.start {
                    return $0.start < $1.start
                }
                if $0.end != $1.end {
                    return $0.end < $1.end
                }
                return $0.id.stableSortKey < $1.id.stableSortKey
            }

        var laneEnds: [Double] = []
        var endingLanes = Heap<TimelineLaneAvailability>()
        var availableLanes = Heap<Int>()
        var result: [TimelineLaneAssignment] = []
        result.reserveCapacity(sorted.count)

        for interval in sorted {
            releaseAvailableLanes(
                startingAt: interval.start,
                laneEnds: laneEnds,
                minimumGap: gap,
                allowsReuseAtMinimumGap: allowsReuseAtMinimumGap,
                endingLanes: &endingLanes,
                availableLanes: &availableLanes
            )
            let lane = availableLanes.popMin() ?? laneEnds.count

            if lane == laneEnds.count {
                laneEnds.append(interval.end)
            } else {
                laneEnds[lane] = interval.end
            }
            endingLanes.insert(
                TimelineLaneAvailability(lane: lane, end: interval.end)
            )
            result.append(TimelineLaneAssignment(id: interval.id, lane: lane))
        }

        return result
    }

    private static func releaseAvailableLanes(
        startingAt start: Double,
        laneEnds: [Double],
        minimumGap: Double,
        allowsReuseAtMinimumGap: Bool,
        endingLanes: inout Heap<TimelineLaneAvailability>,
        availableLanes: inout Heap<Int>
    ) {
        while let candidate = endingLanes.min {
            guard laneEnds.indices.contains(candidate.lane),
                  laneEnds[candidate.lane] == candidate.end
            else {
                _ = endingLanes.popMin()
                continue
            }
            let separation = start - candidate.end
            let canReuse = allowsReuseAtMinimumGap
                ? separation >= minimumGap
                : separation > minimumGap
            guard canReuse else {
                return
            }
            _ = endingLanes.popMin()
            availableLanes.insert(candidate.lane)
        }
    }
}

private nonisolated struct TimelineLaneAvailability: Comparable, Sendable {
    let lane: Int
    let end: Double

    static func < (
        lhs: TimelineLaneAvailability,
        rhs: TimelineLaneAvailability
    ) -> Bool {
        if lhs.end != rhs.end {
            return lhs.end < rhs.end
        }
        return lhs.lane < rhs.lane
    }
}
