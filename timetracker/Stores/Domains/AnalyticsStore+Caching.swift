import Foundation

extension AnalyticsStore {
    func cachedSnapshot(for range: AnalyticsRange) -> AnalyticsSnapshot? {
        snapshots[range]
    }

    func cachedSnapshot(
        for range: AnalyticsRange,
        evaluationKey: AnalyticsEvaluationCacheKey
    ) -> AnalyticsSnapshot? {
        guard snapshotEvaluationKeys[range] == evaluationKey else { return nil }
        return snapshots[range]
    }

    func cachedSnapshot(
        for range: AnalyticsRange,
        now: Date,
        liveRefreshBucket: Int? = nil,
        calendar: Calendar = .current
    ) -> AnalyticsSnapshot? {
        let evaluation = range.evaluation(
            referenceDate: now,
            liveNow: now,
            calendar: calendar
        )
        return cachedSnapshot(
            for: range,
            evaluationKey: AnalyticsEvaluationCacheKey(
                evaluation: evaluation,
                liveRefreshBucket: liveRefreshBucket,
                calendar: calendar
            )
        )
    }

    func cachedTaskSnapshot(
        taskID: UUID,
        range: AnalyticsRange,
        evaluationKey: AnalyticsEvaluationCacheKey
    ) -> TaskAnalyticsSnapshot? {
        taskSnapshots[TaskSnapshotCacheKey(
            taskID: taskID,
            range: range,
            evaluationKey: evaluationKey
        )]
    }

    func cachedTaskSnapshot(
        taskID: UUID,
        range: AnalyticsRange,
        now: Date,
        liveRefreshBucket: Int?,
        calendar: Calendar = .current
    ) -> TaskAnalyticsSnapshot? {
        let evaluation = range.evaluation(
            referenceDate: now,
            liveNow: now,
            calendar: calendar
        )
        return cachedTaskSnapshot(
            taskID: taskID,
            range: range,
            evaluationKey: AnalyticsEvaluationCacheKey(
                evaluation: evaluation,
                liveRefreshBucket: liveRefreshBucket,
                calendar: calendar
            )
        )
    }

    mutating func cacheTaskSnapshot(
        _ snapshot: TaskAnalyticsSnapshot,
        evaluationKey: AnalyticsEvaluationCacheKey
    ) {
        let cacheKey = TaskSnapshotCacheKey(
            taskID: snapshot.taskID,
            range: snapshot.range,
            evaluationKey: evaluationKey
        )
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

    mutating func cacheTaskSnapshot(
        _ snapshot: TaskAnalyticsSnapshot,
        now: Date,
        liveRefreshBucket: Int?,
        calendar: Calendar = .current
    ) {
        let evaluation = snapshot.range.evaluation(
            referenceDate: now,
            liveNow: now,
            calendar: calendar
        )
        cacheTaskSnapshot(
            snapshot,
            evaluationKey: AnalyticsEvaluationCacheKey(
                evaluation: evaluation,
                liveRefreshBucket: liveRefreshBucket,
                calendar: calendar
            )
        )
    }

    mutating func cachedDailySnapshot(
        range: AnalyticsRange,
        tasks: [TaskNode],
        taskCategories: [TaskCategory],
        taskCategoryAssignments: [TaskCategoryAssignment],
        rangeSegments: [TimeSegment],
        allSegments: [TimeSegment],
        sessions: [TimeSession],
        taskPathByID: [UUID: String],
        taskParentPathByID: [UUID: String],
        period: DateInterval,
        evaluatedAt cutoff: Date,
        visualSnapshot: AnalyticsVisualSnapshot? = nil,
        calendar: Calendar
    ) -> AnalyticsSnapshot {
        let daily = cachedDailyBreakdown(
            segments: rangeSegments,
            range: range,
            interval: period,
            evaluatedAt: cutoff,
            calendar: calendar
        )
        return analyticsSnapshot(
            range: range,
            tasks: tasks,
            taskCategories: taskCategories,
            taskCategoryAssignments: taskCategoryAssignments,
            rangeSegments: rangeSegments,
            allSegments: allSegments,
            sessions: sessions,
            taskPathByID: taskPathByID,
            taskParentPathByID: taskParentPathByID,
            daily: daily,
            period: period,
            evaluatedAt: cutoff,
            visualSnapshot: visualSnapshot,
            calendar: calendar
        )
    }

    mutating func invalidateSnapshots(invalidatedIntervals: [DateInterval] = []) {
        snapshots.removeAll(keepingCapacity: true)
        snapshotEvaluationKeys.removeAll(keepingCapacity: true)
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
        snapshotEvaluationKeys.removeAll(keepingCapacity: true)
        taskSnapshots.removeAll(keepingCapacity: true)
    }

    var ledgerBucketCount: Int {
        ledgerBucketCache.bucketCount
    }

    var taskSnapshotCacheCount: Int {
        taskSnapshots.count
    }
}
