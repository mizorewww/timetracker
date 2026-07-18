import Foundation

extension TimeTrackerStore {
    /// Resolves a cache miss without allowing SwiftData objects to cross the
    /// main-actor boundary. The visual read models are a pure, cancellable
    /// value computation; cache publication remains owned by this store.
    func loadAnalyticsSnapshot(
        for range: AnalyticsRange,
        evaluation: AnalyticsPeriodEvaluation,
        calendar: Calendar = .current
    ) async -> AnalyticsSnapshot? {
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
        let visualSnapshot: AnalyticsVisualSnapshot?
        if range == .today {
            let visualInput = AnalyticsVisualSnapshotInput(
                range: range,
                period: evaluation.interval,
                evaluatedAt: evaluation.cutoff,
                calendar: calendar,
                segments: segments,
                tasks: tasks,
                sessions: sessions,
                taskParentPathByID: taskParentPathByID
            )
            guard let resolvedVisualSnapshot = await AnalyticsVisualSnapshotTask.resolve(visualInput),
                  Task.isCancelled == false else {
                return nil
            }
            visualSnapshot = resolvedVisualSnapshot
        } else {
            guard Task.isCancelled == false else { return nil }
            visualSnapshot = nil
        }

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
            visualSnapshot: visualSnapshot,
            calendar: calendar
        )
        guard Task.isCancelled == false else { return nil }
        analyticsDomainStore = store
        return snapshot
    }
}
