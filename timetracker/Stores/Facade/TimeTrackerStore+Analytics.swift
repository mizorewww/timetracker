import Foundation

extension TimeTrackerStore {
    func cachedAnalyticsSnapshot(
        for range: AnalyticsRange,
        evaluation: AnalyticsPeriodEvaluation,
        calendar: Calendar = .current
    ) -> AnalyticsSnapshot? {
        analyticsDomainStore.cachedSnapshot(
            for: range,
            evaluationKey: AnalyticsEvaluationCacheKey(
                evaluation: evaluation,
                liveRefreshBucket: analyticsLiveRefreshBucket(for: evaluation),
                calendar: calendar
            )
        )
    }

    func cachedTaskAnalyticsSnapshot(
        for request: TaskAnalyticsSnapshotRequest
    ) -> TaskAnalyticsSnapshot? {
        analyticsDomainStore.cachedTaskSnapshot(
            taskID: request.taskID,
            range: request.range,
            evaluationKey: request.evaluationKey
        )
    }

    func taskAnalyticsSnapshot(
        for request: TaskAnalyticsSnapshotRequest,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TaskAnalyticsSnapshot? {
        guard let task = task(for: request.taskID) else { return nil }
        if let snapshot = cachedTaskAnalyticsSnapshot(for: request) {
            return snapshot
        }

        let currentInterval = request.evaluationKey.interval
        let previousInterval = analyticsDomainStore.previousDecisionInterval(
            for: request.range,
            currentInterval: currentInterval,
            calendar: calendar
        )
        let decisionInterval = DateInterval(
            start: previousInterval?.start ?? currentInterval.start,
            end: currentInterval.end
        )
        let segments = visibleSegments(
            overlapping: decisionInterval,
            taskIDs: request.taskIDs,
            now: now
        )
        let recentSegments = visibleRecentSegments(forTaskIDs: request.taskIDs)
        let sessions = visibleSessions(for: recentSegments)
        let snapshot = analyticsDomainStore.taskSnapshot(
            range: request.range,
            task: AnalyticsTaskRecord(task),
            taskIDs: request.taskIDs,
            tasks: AnalyticsTaskRecord.records(tasks),
            segments: AnalyticsSegmentRecord.records(segments),
            recentSegments: AnalyticsSegmentRecord.records(recentSegments),
            sessions: AnalyticsSessionRecord.records(sessions),
            taskPathByID: taskPathByID,
            now: now,
            calendar: calendar
        )
        analyticsDomainStore.cacheTaskSnapshot(
            snapshot,
            evaluationKey: request.evaluationKey
        )
        return snapshot
    }

    func taskAnalyticsSnapshotRequest(
        for task: TaskNode,
        range: AnalyticsRange,
        referenceDate: Date,
        liveNow: Date,
        calendar: Calendar = .current
    ) -> TaskAnalyticsSnapshotRequest {
        let taskIDs = taskAndDescendantIDs(for: task.id)
        let evaluation = range.evaluation(
            referenceDate: referenceDate,
            liveNow: liveNow,
            calendar: calendar
        )
        return TaskAnalyticsSnapshotRequest(
            taskID: task.id,
            taskIDs: taskIDs,
            range: range,
            evaluation: evaluation,
            revision: analyticsRevision,
            liveRefreshBucket: analyticsLiveRefreshBucket(
                for: evaluation,
                taskIDs: taskIDs
            ),
            calendar: calendar
        )
    }

    func analyticsLiveRefreshBucket(
        for evaluation: AnalyticsPeriodEvaluation,
        taskIDs: Set<UUID>? = nil
    ) -> Int? {
        guard evaluation.interval.contains(evaluation.clockReference) else { return nil }
        let hasOverlappingActiveSegment = activeSegments.contains { segment in
            guard segment.deletedAt == nil,
                  taskIDs?.contains(segment.taskID) ?? true else { return false }
            return TrackedTimePolicy.overlaps(
                startedAt: segment.startedAt,
                endedAt: segment.endedAt,
                interval: evaluation.interval,
                now: evaluation.cutoff
            )
        }
        guard hasOverlappingActiveSegment else { return nil }
        return Int(evaluation.clockReference.timeIntervalSinceReferenceDate / 60)
    }

    func analyticsSegments(
        for range: AnalyticsRange,
        evaluation: AnalyticsPeriodEvaluation,
        calendar: Calendar
    ) -> [TimeSegment] {
        let current = evaluation.interval
        let previous = analyticsDomainStore.previousDecisionInterval(
            for: range,
            currentInterval: current,
            calendar: calendar
        )
        let interval = DateInterval(start: previous?.start ?? current.start, end: current.end)
        return visibleSegments(
            overlapping: interval,
            now: evaluation.cutoff
        )
    }
}
