import Foundation

extension AnalyticsStore {
    func materializeOverlapWindows(
        _ rawWindows: [RawOverlapWindow],
        expectedExcessSeconds: Int
    ) -> [OverlapAnalyticsPoint] {
        guard !rawWindows.isEmpty else {
            assert(expectedExcessSeconds == 0)
            return []
        }

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

        let points = zip(rawWindows.indices, rawWindows).map { index, window in
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
        .sorted(by: overlapPointPrecedes)
        assert(points.reduce(0) { $0 + $1.excessDurationSeconds } == expectedExcessSeconds)
        return points
    }

    /// Duration models expose whole seconds. Distributing subsecond remainders
    /// here preserves the invariant that detail rows sum exactly to Gross-Wall.
    private func reconcileOverlapSeconds(
        _ allocated: inout [Int],
        exactExcess: [TimeInterval],
        windows: [RawOverlapWindow],
        expectedTotal: Int
    ) {
        var difference = expectedTotal - allocated.reduce(0, +)
        guard difference != 0, !allocated.isEmpty else { return }

        let indexes = allocated.indices.sorted { lhs, rhs in
            let lhsRemainder = exactExcess[lhs] - exactExcess[lhs].rounded(.down)
            let rhsRemainder = exactExcess[rhs] - exactExcess[rhs].rounded(.down)
            if lhsRemainder != rhsRemainder {
                return difference > 0
                    ? lhsRemainder > rhsRemainder
                    : lhsRemainder < rhsRemainder
            }
            return rawWindowPrecedes(windows[lhs], windows[rhs])
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

    private func overlapPointPrecedes(_ lhs: OverlapAnalyticsPoint, _ rhs: OverlapAnalyticsPoint) -> Bool {
        if lhs.excessDurationSeconds != rhs.excessDurationSeconds {
            return lhs.excessDurationSeconds > rhs.excessDurationSeconds
        }
        if lhs.wallDurationSeconds != rhs.wallDurationSeconds {
            return lhs.wallDurationSeconds > rhs.wallDurationSeconds
        }
        if lhs.start != rhs.start {
            return lhs.start < rhs.start
        }
        if lhs.end != rhs.end {
            return lhs.end < rhs.end
        }
        if lhs.concurrentSegmentCount != rhs.concurrentSegmentCount {
            return lhs.concurrentSegmentCount > rhs.concurrentSegmentCount
        }
        return lhs.visibleParticipants.map { $0.id.uuidString }.lexicographicallyPrecedes(
            rhs.visibleParticipants.map { $0.id.uuidString }
        )
    }

    private func rawWindowPrecedes(_ lhs: RawOverlapWindow, _ rhs: RawOverlapWindow) -> Bool {
        if lhs.start != rhs.start {
            return lhs.start < rhs.start
        }
        if lhs.end != rhs.end {
            return lhs.end < rhs.end
        }
        return lhs.concurrentSegmentCount > rhs.concurrentSegmentCount
    }
}
