import Foundation

extension TimeTrackerStore {
    func analyticsSnapshot(for range: AnalyticsRange, now: Date = Date()) -> AnalyticsSnapshot {
        makeAnalyticsSnapshot(for: range, now: now)
    }

    func cachedAnalyticsSnapshot(for range: AnalyticsRange) -> AnalyticsSnapshot? {
        analyticsDomainStore.cachedSnapshot(for: range)
    }

    func refreshAnalyticsSnapshot(for range: AnalyticsRange, now: Date = Date()) {
        var store = analyticsDomainStore
        store.refreshSnapshot(
            range: range,
            tasks: tasks,
            segments: allSegments,
            sessions: sessions,
            taskPathByID: taskPathByID,
            taskParentPathByID: taskParentPathByID,
            now: now
        )
        analyticsDomainStore = store
    }

    func refreshCachedAnalyticsSnapshots(now: Date = Date()) {
        var store = analyticsDomainStore
        store.refreshCachedSnapshots(
            tasks: tasks,
            segments: allSegments,
            sessions: sessions,
            taskPathByID: taskPathByID,
            taskParentPathByID: taskParentPathByID,
            now: now
        )
        analyticsDomainStore = store
    }

    private func makeAnalyticsSnapshot(for range: AnalyticsRange, now: Date = Date()) -> AnalyticsSnapshot {
        analyticsDomainStore.snapshot(
            range: range,
            tasks: tasks,
            segments: allSegments,
            sessions: sessions,
            taskPathByID: taskPathByID,
            taskParentPathByID: taskParentPathByID,
            now: now
        )
    }

    func analyticsOverview(for range: AnalyticsRange, now: Date = Date()) -> AnalyticsOverview {
        analyticsSnapshot(for: range, now: now).overview
    }

    func dailyBreakdown(range: AnalyticsRange, now: Date = Date()) -> [DailyAnalyticsPoint] {
        analyticsSnapshot(for: range, now: now).daily
    }

    func hourlyBreakdown(for date: Date = Date(), now: Date = Date()) -> [HourlyAnalyticsPoint] {
        analyticsEngine.hourlyBreakdown(segments: allSegments, date: date, now: now)
    }

    func taskBreakdown(range: AnalyticsRange, now: Date = Date()) -> [TaskAnalyticsPoint] {
        analyticsSnapshot(for: range, now: now).taskBreakdown
    }

    func overlapSegments(range: AnalyticsRange, now: Date = Date()) -> [OverlapAnalyticsPoint] {
        analyticsSnapshot(for: range, now: now).overlaps
    }
}
