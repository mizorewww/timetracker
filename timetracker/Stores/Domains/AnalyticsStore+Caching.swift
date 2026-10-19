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
        taskSnapshotOrder.removeAll { staleKeys.contains($0) || $0 == cacheKey }
        taskSnapshots[cacheKey] = snapshot
        taskSnapshotOrder.append(cacheKey)

        // Evict the least recently stored task snapshots first.
        while taskSnapshotOrder.count > Self.maximumTaskSnapshotCount {
            taskSnapshots.removeValue(forKey: taskSnapshotOrder.removeFirst())
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

    mutating func invalidateSnapshots() {
        snapshots.removeAll(keepingCapacity: true)
        snapshotEvaluationKeys.removeAll(keepingCapacity: true)
        taskSnapshots.removeAll(keepingCapacity: true)
        taskSnapshotOrder.removeAll(keepingCapacity: true)
    }
}
