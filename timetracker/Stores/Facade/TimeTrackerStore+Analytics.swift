import Foundation

extension TimeTrackerStore {
    func analyticsSnapshot(for range: AnalyticsRange, now: Date = Date()) -> AnalyticsSnapshot {
        let liveRefreshBucket = analyticsLiveRefreshBucket(for: range, now: now)
        if let snapshot = analyticsDomainStore.cachedSnapshot(
            for: range,
            now: now,
            liveRefreshBucket: liveRefreshBucket
        ) {
            return snapshot
        }

        let segments = analyticsSegments(for: range, now: now)
        let sessions = visibleSessions(for: segments)
        var store = analyticsDomainStore
        let snapshot = store.refreshSnapshot(
            range: range,
            tasks: tasks,
            taskCategories: taskCategories,
            taskCategoryAssignments: taskCategoryAssignments,
            segments: segments,
            sessions: sessions,
            taskPathByID: taskPathByID,
            taskParentPathByID: taskParentPathByID,
            now: now,
            liveRefreshBucket: liveRefreshBucket
        )
        analyticsDomainStore = store
        return snapshot
    }

    func cachedAnalyticsSnapshot(for range: AnalyticsRange) -> AnalyticsSnapshot? {
        analyticsDomainStore.cachedSnapshot(for: range)
    }

    func refreshAnalyticsSnapshot(for range: AnalyticsRange, now: Date = Date()) {
        let segments = analyticsSegments(for: range, now: now)
        let sessions = visibleSessions(for: segments)
        var store = analyticsDomainStore
        store.refreshSnapshot(
            range: range,
            tasks: tasks,
            taskCategories: taskCategories,
            taskCategoryAssignments: taskCategoryAssignments,
            segments: segments,
            sessions: sessions,
            taskPathByID: taskPathByID,
            taskParentPathByID: taskParentPathByID,
            now: now
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
        guard let interval = range.interval(containing: now, calendar: calendar) else { return nil }
        let hasOverlappingActiveSegment = activeSegments.contains { segment in
            guard segment.deletedAt == nil,
                  taskIDs?.contains(segment.taskID) ?? true else { return false }
            return TrackedTimePolicy.overlaps(
                startedAt: segment.startedAt,
                endedAt: segment.endedAt,
                interval: interval,
                now: now
            )
        }
        guard hasOverlappingActiveSegment else { return nil }
        return Int(now.timeIntervalSinceReferenceDate / 60)
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

    private func analyticsSegments(for range: AnalyticsRange, now: Date) -> [TimeSegment] {
        guard let current = range.interval(containing: now, calendar: .current) else { return [] }
        let previous = analyticsDomainStore.previousDecisionInterval(
            for: range,
            currentInterval: current,
            calendar: .current
        )
        let interval = DateInterval(start: previous?.start ?? current.start, end: current.end)
        return visibleSegments(overlapping: interval, now: now)
    }
}
