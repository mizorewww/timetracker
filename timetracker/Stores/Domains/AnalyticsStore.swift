import Foundation

struct AnalyticsStore {
    static let maximumTaskSnapshotCount = 24

    struct TaskSnapshotCacheKey: Hashable {
        let taskID: UUID
        let range: AnalyticsRange
        let evaluationKey: AnalyticsEvaluationCacheKey
    }

    var snapshots: [AnalyticsRange: AnalyticsSnapshot] = [:]
    var snapshotEvaluationKeys: [AnalyticsRange: AnalyticsEvaluationCacheKey] = [:]
    var taskSnapshots: [TaskSnapshotCacheKey: TaskAnalyticsSnapshot] = [:]
    /// Insertion order of `taskSnapshots`, oldest first, for eviction.
    var taskSnapshotOrder: [TaskSnapshotCacheKey] = []

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
            let snapshot = analyticsSnapshot(
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
                daily: dailyBreakdown(
                    segments: rangeSegments,
                    range: range,
                    interval: period,
                    evaluatedAt: cutoff,
                    calendar: calendar
                ),
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
