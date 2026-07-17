import Foundation

nonisolated extension AnalyticsVisualOverlapService {
    func materializeOverlapWindows(
        _ rawWindows: [AnalyticsVisualRawOverlapWindow],
        expectedExcessSeconds: Int
    ) -> [OverlapAnalyticsPoint] {
        guard rawWindows.isEmpty == false else { return [] }
        let exactExcess = rawWindows.map { window in
            max(
                0,
                window.end.timeIntervalSince(window.start)
                    * Double(max(0, window.concurrentSegmentCount - 1))
            )
        }
        var allocatedExcess = exactExcess.map { Int($0.rounded(.down)) }
        reconcileOverlapSeconds(
            &allocatedExcess,
            exactExcess: exactExcess,
            windows: rawWindows,
            expectedTotal: max(0, expectedExcessSeconds)
        )
        return zip(rawWindows.indices, rawWindows).map { index, window in
            OverlapAnalyticsPoint(
                start: window.start,
                end: window.end,
                concurrentSegmentCount: window.concurrentSegmentCount,
                participantCount: window.participantCount,
                visibleParticipants: window.visibleParticipants,
                wallDurationSeconds: max(0, Int(window.end.timeIntervalSince(window.start))),
                excessDurationSeconds: allocatedExcess[index]
            )
        }
        .sorted { lhs, rhs in
            if lhs.excessDurationSeconds != rhs.excessDurationSeconds {
                return lhs.excessDurationSeconds > rhs.excessDurationSeconds
            }
            if lhs.wallDurationSeconds != rhs.wallDurationSeconds {
                return lhs.wallDurationSeconds > rhs.wallDurationSeconds
            }
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            if lhs.end != rhs.end { return lhs.end < rhs.end }
            if lhs.concurrentSegmentCount != rhs.concurrentSegmentCount {
                return lhs.concurrentSegmentCount > rhs.concurrentSegmentCount
            }
            return lhs.visibleParticipants.map { $0.id.uuidString }.lexicographicallyPrecedes(
                rhs.visibleParticipants.map { $0.id.uuidString }
            )
        }
    }

    func reconcileOverlapSeconds(
        _ allocated: inout [Int],
        exactExcess: [TimeInterval],
        windows: [AnalyticsVisualRawOverlapWindow],
        expectedTotal: Int
    ) {
        var difference = expectedTotal - allocated.reduce(0, +)
        guard difference != 0, allocated.isEmpty == false else { return }
        let indexes = allocated.indices.sorted { lhs, rhs in
            let lhsRemainder = exactExcess[lhs] - exactExcess[lhs].rounded(.down)
            let rhsRemainder = exactExcess[rhs] - exactExcess[rhs].rounded(.down)
            if lhsRemainder != rhsRemainder {
                return difference > 0
                    ? lhsRemainder > rhsRemainder
                    : lhsRemainder < rhsRemainder
            }
            if windows[lhs].start != windows[rhs].start {
                return windows[lhs].start < windows[rhs].start
            }
            if windows[lhs].end != windows[rhs].end {
                return windows[lhs].end < windows[rhs].end
            }
            return windows[lhs].concurrentSegmentCount > windows[rhs].concurrentSegmentCount
        }
        var allocationCursor = 0
        while difference != 0 {
            let target = indexes[allocationCursor % indexes.count]
            if difference > 0 {
                allocated[target] += 1
                difference -= 1
            } else if allocated[target] > 0 {
                allocated[target] -= 1
                difference += 1
            }
            allocationCursor += 1
        }
    }

    func mergedIntervals(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for interval in sorted {
            guard let last = merged.last else {
                merged.append(interval)
                continue
            }
            if interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(
                    start: last.start,
                    end: max(last.end, interval.end)
                )
            } else {
                merged.append(interval)
            }
        }
        return merged
    }
}
