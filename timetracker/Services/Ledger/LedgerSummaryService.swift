import Foundation

nonisolated enum LedgerSummaryService {
    static func totalSeconds(
        taskIDs: Set<UUID>,
        segments: [TimeSegment],
        mode: AggregationMode = .gross,
        now: Date = Date()
    ) -> Int {
        let filtered = segments
            .visibleDeduplicatedByID()
            .filter { taskIDs.contains($0.taskID) }
        return TimeAggregationService.totalSeconds(segments: filtered, mode: mode, now: now)
    }

    static func secondsInInterval(
        taskIDs: Set<UUID>,
        segments: [TimeSegment],
        interval: DateInterval,
        mode: AggregationMode = .gross,
        now: Date = Date()
    ) -> Int {
        let intervals = segments.visibleDeduplicatedByID().compactMap { segment -> DateInterval? in
            guard taskIDs.contains(segment.taskID) else { return nil }
            return TrackedTimePolicy.interval(
                startedAt: segment.startedAt,
                endedAt: segment.endedAt,
                now: now,
                clippedTo: interval
            )
        }

        switch mode {
        case .gross:
            return intervals.reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start)) }
        case .wallClock:
            return TimeAggregationService.mergeOverlappingIntervals(intervals).reduce(0) {
                $0 + Int($1.end.timeIntervalSince($1.start))
            }
        }
    }
}
