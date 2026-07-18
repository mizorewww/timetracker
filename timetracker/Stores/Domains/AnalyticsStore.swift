import Foundation

struct AnalyticsStore {
    static let maximumTaskSnapshotCount = 24

    struct TaskSnapshotCacheKey: Hashable {
        let taskID: UUID
        let range: AnalyticsRange
        let evaluationKey: AnalyticsEvaluationCacheKey
    }

    var ledgerBucketCache = LedgerBucketCache()
    var snapshots: [AnalyticsRange: AnalyticsSnapshot] = [:]
    var snapshotEvaluationKeys: [AnalyticsRange: AnalyticsEvaluationCacheKey] = [:]
    var taskSnapshots: [TaskSnapshotCacheKey: TaskAnalyticsSnapshot] = [:]

    @discardableResult
    mutating func refreshSnapshot(
        range: AnalyticsRange,
        tasks: [TaskNode],
        taskCategories: [TaskCategory] = [],
        taskCategoryAssignments: [TaskCategoryAssignment] = [],
        segments: [TimeSegment],
        sessions: [TimeSession],
        cancelledPomodoroSessionIDs: Set<UUID> = [],
        taskPathByID: [UUID: String],
        taskParentPathByID: [UUID: String],
        now: Date = Date(),
        liveRefreshBucket: Int? = nil,
        calendar: Calendar = .current
    ) -> AnalyticsSnapshot {
        let evaluation = range.evaluation(
            referenceDate: now,
            liveNow: now,
            calendar: calendar
        )
        return refreshSnapshot(
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
                liveRefreshBucket: liveRefreshBucket,
                calendar: calendar
            ),
            calendar: calendar
        )
    }

    @discardableResult
    mutating func refreshSnapshot(
        range: AnalyticsRange,
        period: DateInterval,
        tasks: [TaskNode],
        taskCategories: [TaskCategory] = [],
        taskCategoryAssignments: [TaskCategoryAssignment] = [],
        segments: [TimeSegment],
        sessions: [TimeSession],
        cancelledPomodoroSessionIDs: Set<UUID> = [],
        taskPathByID: [UUID: String],
        taskParentPathByID: [UUID: String],
        evaluatedAt cutoff: Date,
        liveRefreshBucket: Int? = nil,
        evaluationKey: AnalyticsEvaluationCacheKey,
        visualSnapshot: AnalyticsVisualSnapshot? = nil,
        calendar: Calendar = .current
    ) -> AnalyticsSnapshot {
        PerformanceSignpost.interval("Analytics snapshot generation") {
            let canonicalSegments = segments.deduplicatedByID()
            let rangeSegments = segmentsForAnalytics(
                canonicalSegments,
                interval: period,
                evaluatedAt: cutoff
            )
            let snapshot = cachedDailySnapshot(
                range: range,
                tasks: tasks,
                taskCategories: taskCategories,
                taskCategoryAssignments: taskCategoryAssignments,
                rangeSegments: rangeSegments,
                allSegments: canonicalSegments,
                sessions: sessions,
                cancelledPomodoroSessionIDs: cancelledPomodoroSessionIDs,
                taskPathByID: taskPathByID,
                taskParentPathByID: taskParentPathByID,
                period: period,
                evaluatedAt: cutoff,
                visualSnapshot: visualSnapshot,
                calendar: calendar
            )
            snapshots[range] = snapshot
            snapshotEvaluationKeys[range] = evaluationKey
            return snapshot
        }
    }
}
