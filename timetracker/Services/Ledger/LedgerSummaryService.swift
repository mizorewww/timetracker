import Foundation

struct LedgerSummaryService {
    private let aggregationService = TimeAggregationService()

    func totalSeconds(
        taskIDs: Set<UUID>,
        segments: [TimeSegment],
        mode: AggregationMode = .gross,
        now: Date = Date()
    ) -> Int {
        let filtered = segments.filter { taskIDs.contains($0.taskID) && $0.deletedAt == nil }
        return aggregationService.totalSeconds(segments: filtered, mode: mode, now: now)
    }

    func secondsInInterval(
        taskIDs: Set<UUID>,
        segments: [TimeSegment],
        interval: DateInterval,
        mode: AggregationMode = .gross,
        now: Date = Date()
    ) -> Int {
        let intervals = segments.compactMap { segment -> DateInterval? in
            guard taskIDs.contains(segment.taskID), segment.deletedAt == nil else { return nil }
            let end = segment.endedAt ?? now
            guard segment.startedAt < interval.end, end > interval.start else { return nil }
            let start = max(segment.startedAt, interval.start)
            let clippedEnd = min(end, interval.end)
            guard clippedEnd > start else { return nil }
            return DateInterval(start: start, end: clippedEnd)
        }

        switch mode {
        case .gross:
            return intervals.reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start)) }
        case .wallClock:
            return aggregationService.mergeOverlappingIntervals(intervals).reduce(0) {
                $0 + Int($1.end.timeIntervalSince($1.start))
            }
        }
    }
}
