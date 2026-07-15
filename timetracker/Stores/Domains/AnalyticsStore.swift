import Foundation

struct AnalyticsStore {
    private static let maximumTaskSnapshotCount = 24

    private struct TaskSnapshotCacheKey: Hashable {
        let taskID: UUID
        let range: AnalyticsRange
        let intervalStart: Date
        let liveRefreshBucket: Int?
    }

    var ledgerBucketCache = LedgerBucketCache()
    private(set) var snapshots: [AnalyticsRange: AnalyticsSnapshot] = [:]
    private(set) var snapshotIntervalStarts: [AnalyticsRange: Date] = [:]
    private var snapshotLiveRefreshBuckets: [AnalyticsRange: Int] = [:]
    private var taskSnapshots: [TaskSnapshotCacheKey: TaskAnalyticsSnapshot] = [:]

    func cachedSnapshot(for range: AnalyticsRange) -> AnalyticsSnapshot? {
        snapshots[range]
    }

    func cachedSnapshot(
        for range: AnalyticsRange,
        now: Date,
        liveRefreshBucket: Int? = nil,
        calendar: Calendar = .current
    ) -> AnalyticsSnapshot? {
        guard let cachedIntervalStart = snapshotIntervalStarts[range],
              let requestedIntervalStart = range.interval(containing: now, calendar: calendar)?.start,
              cachedIntervalStart == requestedIntervalStart else {
            return nil
        }
        guard snapshotLiveRefreshBuckets[range] == liveRefreshBucket else { return nil }
        return snapshots[range]
    }

    @discardableResult
    mutating func refreshSnapshot(
        range: AnalyticsRange,
        tasks: [TaskNode],
        taskCategories: [TaskCategory] = [],
        taskCategoryAssignments: [TaskCategoryAssignment] = [],
        segments: [TimeSegment],
        sessions: [TimeSession],
        taskPathByID: [UUID: String],
        taskParentPathByID: [UUID: String],
        now: Date = Date(),
        liveRefreshBucket: Int? = nil,
        calendar: Calendar = .current
    ) -> AnalyticsSnapshot {
        PerformanceSignpost.interval("Analytics snapshot generation") {
            let canonicalSegments = segments.deduplicatedByID()
            let rangeSegments = segmentsForAnalytics(
                canonicalSegments,
                range: range,
                now: now,
                calendar: calendar
            )
            let snapshot = cachedDailySnapshot(
                range: range,
                tasks: tasks,
                taskCategories: taskCategories,
                taskCategoryAssignments: taskCategoryAssignments,
                rangeSegments: rangeSegments,
                allSegments: canonicalSegments,
                sessions: sessions,
                taskPathByID: taskPathByID,
                taskParentPathByID: taskParentPathByID,
                now: now,
                calendar: calendar
            )
            snapshots[range] = snapshot
            snapshotIntervalStarts[range] = range.interval(containing: now, calendar: calendar)?.start
            if let liveRefreshBucket {
                snapshotLiveRefreshBuckets[range] = liveRefreshBucket
            } else {
                snapshotLiveRefreshBuckets.removeValue(forKey: range)
            }
            return snapshot
        }
    }

    func cachedTaskSnapshot(
        taskID: UUID,
        range: AnalyticsRange,
        now: Date,
        liveRefreshBucket: Int?,
        calendar: Calendar = .current
    ) -> TaskAnalyticsSnapshot? {
        guard let intervalStart = range.interval(containing: now, calendar: calendar)?.start else { return nil }
        return taskSnapshots[TaskSnapshotCacheKey(
            taskID: taskID,
            range: range,
            intervalStart: intervalStart,
            liveRefreshBucket: liveRefreshBucket
        )]
    }

    mutating func cacheTaskSnapshot(
        _ snapshot: TaskAnalyticsSnapshot,
        now: Date,
        liveRefreshBucket: Int?,
        calendar: Calendar = .current
    ) {
        guard let intervalStart = snapshot.range.interval(containing: now, calendar: calendar)?.start else { return }
        let cacheKey = TaskSnapshotCacheKey(
            taskID: snapshot.taskID,
            range: snapshot.range,
            intervalStart: intervalStart,
            liveRefreshBucket: liveRefreshBucket
        )

        // A running timer changes the live bucket every minute. Keeping every
        // previous bucket retains complete task snapshots indefinitely, so each
        // task/range owns only its newest entry and the overall cache is bounded.
        let staleKeys = taskSnapshots.keys.filter {
            $0.taskID == cacheKey.taskID && $0.range == cacheKey.range
        }
        for staleKey in staleKeys {
            taskSnapshots.removeValue(forKey: staleKey)
        }
        taskSnapshots[cacheKey] = snapshot

        let excessCount = taskSnapshots.count - Self.maximumTaskSnapshotCount
        if excessCount > 0 {
            let evictionKeys = taskSnapshots.keys.filter { $0 != cacheKey }.prefix(excessCount)
            for evictionKey in evictionKeys {
                taskSnapshots.removeValue(forKey: evictionKey)
            }
        }
    }

    mutating func invalidateSnapshots(invalidatedIntervals: [DateInterval] = []) {
        snapshots.removeAll(keepingCapacity: true)
        snapshotIntervalStarts.removeAll(keepingCapacity: true)
        snapshotLiveRefreshBuckets.removeAll(keepingCapacity: true)
        taskSnapshots.removeAll(keepingCapacity: true)
        if invalidatedIntervals.isEmpty {
            ledgerBucketCache.removeAll()
        } else {
            ledgerBucketCache.invalidate(intervals: invalidatedIntervals)
        }
    }

    mutating func invalidateLedgerBuckets(intervals: [DateInterval]) {
        ledgerBucketCache.invalidate(intervals: intervals)
    }

    mutating func clearLedgerBuckets() {
        ledgerBucketCache.removeAll()
        snapshots.removeAll(keepingCapacity: true)
        snapshotIntervalStarts.removeAll(keepingCapacity: true)
        snapshotLiveRefreshBuckets.removeAll(keepingCapacity: true)
        taskSnapshots.removeAll(keepingCapacity: true)
    }

    var ledgerBucketCount: Int {
        ledgerBucketCache.bucketCount
    }

    var taskSnapshotCacheCount: Int {
        taskSnapshots.count
    }
}
