import Foundation

struct AnalyticsStore {
    var ledgerBucketCache = LedgerBucketCache()
    private(set) var snapshots: [AnalyticsRange: AnalyticsSnapshot] = [:]

    func cachedSnapshot(for range: AnalyticsRange) -> AnalyticsSnapshot? {
        snapshots[range]
    }

    @discardableResult
    mutating func refreshSnapshot(
        range: AnalyticsRange,
        tasks: [TaskNode],
        segments: [TimeSegment],
        sessions: [TimeSession],
        taskPathByID: [UUID: String],
        taskParentPathByID: [UUID: String],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AnalyticsSnapshot {
        PerformanceSignpost.interval("Analytics snapshot generation") {
            let rangeSegments = segmentsForAnalytics(segments, range: range, now: now, calendar: calendar)
            let snapshot = cachedDailySnapshot(
                range: range,
                tasks: tasks,
                rangeSegments: rangeSegments,
                sessions: sessions,
                taskPathByID: taskPathByID,
                taskParentPathByID: taskParentPathByID,
                now: now,
                calendar: calendar
            )
            snapshots[range] = snapshot
            return snapshot
        }
    }

    mutating func refreshCachedSnapshots(
        tasks: [TaskNode],
        segments: [TimeSegment],
        sessions: [TimeSession],
        taskPathByID: [UUID: String],
        taskParentPathByID: [UUID: String],
        now: Date = Date(),
        calendar: Calendar = .current,
        invalidatedIntervals: [DateInterval] = []
    ) {
        guard !snapshots.isEmpty else { return }
        ledgerBucketCache.invalidate(intervals: invalidatedIntervals)
        for range in Array(snapshots.keys) {
            refreshSnapshot(
                range: range,
                tasks: tasks,
                segments: segments,
                sessions: sessions,
                taskPathByID: taskPathByID,
                taskParentPathByID: taskParentPathByID,
                now: now,
                calendar: calendar
            )
        }
    }

    mutating func invalidateLedgerBuckets(intervals: [DateInterval]) {
        ledgerBucketCache.invalidate(intervals: intervals)
    }

    mutating func clearLedgerBuckets() {
        ledgerBucketCache.removeAll()
    }

    var ledgerBucketCount: Int {
        ledgerBucketCache.bucketCount
    }
}
