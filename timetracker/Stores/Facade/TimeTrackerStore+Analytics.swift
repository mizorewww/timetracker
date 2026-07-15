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
        if let snapshot = analyticsDomainStore.cachedSnapshot(
            for: range,
            period: evaluation.interval,
            liveRefreshBucket: liveRefreshBucket
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
            taskPathByID: taskPathByID,
            taskParentPathByID: taskParentPathByID,
            evaluatedAt: evaluation.cutoff,
            liveRefreshBucket: liveRefreshBucket,
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
            taskPathByID: taskPathByID,
            taskParentPathByID: taskParentPathByID,
            evaluatedAt: evaluation.cutoff
        )
        analyticsDomainStore = store
    }

    func invalidateAnalyticsSnapshots(invalidatedIntervals: [DateInterval] = []) {
        var store = analyticsDomainStore
        store.invalidateSnapshots(invalidatedIntervals: invalidatedIntervals)
        analyticsDomainStore = store
    }

    func taskAnalyticsSnapshot(
        for task: TaskNode,
        range: AnalyticsRange,
        now: Date = Date()
    ) -> TaskAnalyticsSnapshot {
        let taskIDs = taskAndDescendantIDs(for: task.id)
        let liveRefreshBucket = analyticsLiveRefreshBucket(for: range, now: now, taskIDs: taskIDs)
        if let snapshot = analyticsDomainStore.cachedTaskSnapshot(
            taskID: task.id,
            range: range,
            now: now,
            liveRefreshBucket: liveRefreshBucket
        ) {
            return snapshot
        }

        let segments = visibleSegments(forTaskIDs: taskIDs)
        let sessions = visibleSessions(for: segments)
        var store = analyticsDomainStore
        let snapshot = store.taskSnapshot(
            range: range,
            task: task,
            taskIDs: taskIDs,
            tasks: tasks,
            segments: segments,
            sessions: sessions,
            taskPathByID: taskPathByID,
            now: now
        )
        store.cacheTaskSnapshot(snapshot, now: now, liveRefreshBucket: liveRefreshBucket)
        analyticsDomainStore = store
        return snapshot
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

    func analyticsOverview(for range: AnalyticsRange, now: Date = Date()) -> AnalyticsOverview {
        analyticsSnapshot(for: range, now: now).overview
    }

    func dailyBreakdown(range: AnalyticsRange, now: Date = Date()) -> [DailyAnalyticsPoint] {
        analyticsSnapshot(for: range, now: now).daily
    }

    func hourlyBreakdown(for date: Date = Date(), now: Date = Date()) -> [HourlyAnalyticsPoint] {
        guard let interval = Calendar.current.dateInterval(of: .day, for: date) else { return [] }
        return analyticsEngine.hourlyBreakdown(
            segments: visibleSegments(overlapping: interval, now: now),
            date: date,
            now: now
        )
    }

    func taskBreakdown(range: AnalyticsRange, now: Date = Date()) -> [TaskAnalyticsPoint] {
        analyticsSnapshot(for: range, now: now).taskBreakdown
    }

    func overlapSegments(range: AnalyticsRange, now: Date = Date()) -> [OverlapAnalyticsPoint] {
        analyticsSnapshot(for: range, now: now).overlaps
    }

    private func analyticsSegments(
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
