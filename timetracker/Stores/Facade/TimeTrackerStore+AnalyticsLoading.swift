import Foundation

extension TimeTrackerStore {
    /// Resolves a cache miss: captures value records of the period's rows on
    /// the main actor, aggregates them off it, and caches the result unless
    /// the load was cancelled or the ledger changed meanwhile.
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
        let revision = analyticsRevision
        guard let snapshot = await AnalyticsStore.buildSnapshot(input),
              Task.isCancelled == false,
              analyticsRevision == revision
        else {
            return nil
        }
        analyticsDomainStore.storeSnapshot(snapshot, evaluationKey: evaluationKey)
        return snapshot
    }
}
