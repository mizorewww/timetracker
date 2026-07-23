import Foundation

extension TimeTrackerStore {
    func analyticsSnapshot(for range: AnalyticsRange, now: Date = Date()) -> AnalyticsSnapshot {
        analyticsSnapshot(
            for: range,
            evaluation: range.evaluation(referenceDate: now, liveNow: now)
        )
    }

    func analyticsSnapshot(
        for range: AnalyticsRange,
        evaluation: AnalyticsPeriodEvaluation,
        calendar: Calendar = .current
    ) -> AnalyticsSnapshot {
        let liveRefreshBucket = analyticsLiveRefreshBucket(for: evaluation)
        let evaluationKey = AnalyticsEvaluationCacheKey(
            evaluation: evaluation,
            liveRefreshBucket: liveRefreshBucket,
            calendar: calendar
        )
        if let snapshot = analyticsDomainStore.cachedSnapshot(
            for: range,
            evaluationKey: evaluationKey
        ) {
            return snapshot
        }

        let segments = analyticsSegments(
            for: range,
            evaluation: evaluation,
            calendar: calendar
        )
        let sessions = visibleSessions(for: segments)
        var store = analyticsDomainStore
        let snapshot = store.refreshSnapshot(
            range: range,
            period: evaluation.interval,
            tasks: tasks,
            taskCategories: taskCategories,
            taskCategoryAssignments: taskCategoryAssignments,
            segments: segments,
            sessions: sessions,
            cancelledPomodoroSessionIDs: cancelledPomodoroSessionIDs,
            taskPathByID: taskPathByID,
            taskParentPathByID: taskParentPathByID,
            evaluatedAt: evaluation.cutoff,
            liveRefreshBucket: liveRefreshBucket,
            evaluationKey: evaluationKey,
            calendar: calendar
        )
        analyticsDomainStore = store
        return snapshot
    }

    func cachedAnalyticsSnapshot(for range: AnalyticsRange) -> AnalyticsSnapshot? {
        analyticsDomainStore.cachedSnapshot(for: range)
    }

    func refreshAnalyticsSnapshot(for range: AnalyticsRange, now: Date = Date()) {
        let evaluation = range.evaluation(referenceDate: now, liveNow: now)
        let liveRefreshBucket = analyticsLiveRefreshBucket(for: evaluation)
        let segments = analyticsSegments(
            for: range,
            evaluation: evaluation,
            calendar: .current
        )
        let sessions = visibleSessions(for: segments)
        var store = analyticsDomainStore
        store.refreshSnapshot(
            range: range,
            period: evaluation.interval,
            tasks: tasks,
            taskCategories: taskCategories,
            taskCategoryAssignments: taskCategoryAssignments,
            segments: segments,
            sessions: sessions,
            cancelledPomodoroSessionIDs: cancelledPomodoroSessionIDs,
            taskPathByID: taskPathByID,
            taskParentPathByID: taskParentPathByID,
            evaluatedAt: evaluation.cutoff,
            liveRefreshBucket: liveRefreshBucket,
            evaluationKey: AnalyticsEvaluationCacheKey(
                evaluation: evaluation,
                liveRefreshBucket: liveRefreshBucket
            )
        )
        analyticsDomainStore = store
    }

    func invalidateAnalyticsSnapshots(invalidatedIntervals: [DateInterval] = []) {
        var store = analyticsDomainStore
        store.invalidateSnapshots(invalidatedIntervals: invalidatedIntervals)
        analyticsDomainStore = store
    }

    func taskAnalyticsSnapshot(
        for request: TaskAnalyticsSnapshotRequest,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TaskAnalyticsSnapshot? {
        guard let task = task(for: request.taskID) else { return nil }
        if let snapshot = analyticsDomainStore.cachedTaskSnapshot(
            taskID: request.taskID,
            range: request.range,
            evaluationKey: request.evaluationKey
        ) {
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
            evaluatedAt: now,
            clockReference: now
        )
        let recentSegments = visibleRecentSegments(forTaskIDs: request.taskIDs)
        let sessions = visibleSessions(for: recentSegments)
        var store = analyticsDomainStore
        let snapshot = store.taskSnapshot(
            range: request.range,
            task: task,
            taskIDs: request.taskIDs,
            tasks: tasks,
            segments: segments,
            recentSegments: recentSegments,
            sessions: sessions,
            taskPathByID: taskPathByID,
            now: now,
            calendar: calendar
        )
        store.cacheTaskSnapshot(
            snapshot,
            evaluationKey: request.evaluationKey
        )
        analyticsDomainStore = store
        return snapshot
    }

    func taskAnalyticsSnapshotRequest(
        for task: TaskNode,
        range: AnalyticsRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TaskAnalyticsSnapshotRequest {
        taskAnalyticsSnapshotRequest(
            for: task,
            range: range,
            referenceDate: now,
            liveNow: now,
            calendar: calendar
        )
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
        for range: AnalyticsRange,
        now: Date,
        taskIDs: Set<UUID>? = nil,
        calendar: Calendar = .current
    ) -> Int? {
        analyticsLiveRefreshBucket(
            for: range.evaluation(
                referenceDate: now,
                liveNow: now,
                calendar: calendar
            ),
            taskIDs: taskIDs
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
            evaluatedAt: evaluation.cutoff,
            clockReference: evaluation.clockReference
        )
    }
}
