import Foundation

struct AnalyticsSnapshotLoadKey: Hashable {
    let range: AnalyticsRange
    let evaluationKey: AnalyticsEvaluationCacheKey
    let analyticsRevision: UInt
}

extension TimeTrackerStore {
    /// Resolves a cache miss: captures value records of the period's rows on
    /// the main actor, aggregates them off it, and caches the result unless
    /// the ledger changed meanwhile. Pages asking for the same period while
    /// it aggregates (Analytics and a pushed category detail) share one load.
    func loadAnalyticsSnapshot(
        for range: AnalyticsRange,
        evaluation: AnalyticsPeriodEvaluation,
        calendar: Calendar = .current
    ) async -> AnalyticsSnapshot? {
        let evaluationKey = AnalyticsEvaluationCacheKey(
            evaluation: evaluation,
            liveRefreshBucket: analyticsLiveRefreshBucket(for: evaluation),
            calendar: calendar
        )
        if let snapshot = analyticsDomainStore.cachedSnapshot(
            for: range,
            evaluationKey: evaluationKey
        ) {
            return snapshot
        }

        let revision = analyticsRevision
        let loadKey = AnalyticsSnapshotLoadKey(
            range: range,
            evaluationKey: evaluationKey,
            analyticsRevision: revision
        )
        let load = analyticsSnapshotLoads[loadKey] ?? startAnalyticsSnapshotLoad(
            for: range,
            evaluation: evaluation,
            calendar: calendar,
            key: loadKey
        )
        let snapshot = await load.value
        analyticsSnapshotLoads[loadKey] = nil
        guard analyticsRevision == revision else {
            return nil
        }
        analyticsDomainStore.storeSnapshot(snapshot, evaluationKey: evaluationKey)
        return snapshot
    }

    private func startAnalyticsSnapshotLoad(
        for range: AnalyticsRange,
        evaluation: AnalyticsPeriodEvaluation,
        calendar: Calendar,
        key: AnalyticsSnapshotLoadKey
    ) -> Task<AnalyticsSnapshot, Never> {
        let segments = analyticsSegments(
            for: range,
            evaluation: evaluation,
            calendar: calendar
        )
        let input = AnalyticsSnapshotInput(
            range: range,
            period: evaluation.interval,
            evaluatedAt: evaluation.cutoff,
            calendar: calendar,
            tasks: tasks,
            taskCategories: taskCategories,
            taskCategoryAssignments: taskCategoryAssignments,
            segments: segments,
            sessions: visibleSessions(for: segments),
            cancelledPomodoroSessionIDs: cancelledPomodoroSessionIDs,
            taskPathByID: taskPathByID,
            taskParentPathByID: taskParentPathByID
        )
        let load = Task { await AnalyticsStore.buildSnapshot(input) }
        analyticsSnapshotLoads[key] = load
        return load
    }
}
