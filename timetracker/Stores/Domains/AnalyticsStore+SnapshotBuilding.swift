import Foundation

nonisolated extension AnalyticsStore {
    /// Aggregates `input` off the main actor; nil when the caller's task was
    /// cancelled. The aggregation reads only value records, never the cache.
    @concurrent
    static func buildSnapshot(_ input: AnalyticsSnapshotInput) async -> AnalyticsSnapshot? {
        guard Task.isCancelled == false else { return nil }
        let snapshot = AnalyticsStore().snapshot(input)
        return Task.isCancelled ? nil : snapshot
    }

    func snapshot(_ input: AnalyticsSnapshotInput) -> AnalyticsSnapshot {
        PerformanceSignpost.interval("Analytics snapshot generation") {
            let rangeSegments = segmentsForAnalytics(
                input.segments,
                interval: input.period,
                evaluatedAt: input.evaluatedAt
            )
            return analyticsSnapshot(
                range: input.range,
                tasks: input.tasks,
                taskCategories: input.taskCategories,
                categoryIDByRootTaskID: input.categoryIDByRootTaskID,
                rangeSegments: rangeSegments,
                allSegments: input.segments,
                sessions: input.sessions,
                cancelledPomodoroSessionIDs: input.cancelledPomodoroSessionIDs,
                taskPathByID: input.taskPathByID,
                taskParentPathByID: input.taskParentPathByID,
                daily: dailyBreakdown(
                    segments: rangeSegments,
                    range: input.range,
                    interval: input.period,
                    evaluatedAt: input.evaluatedAt,
                    calendar: input.calendar
                ),
                period: input.period,
                evaluatedAt: input.evaluatedAt,
                calendar: input.calendar
            )
        }
    }

    func analyticsSnapshot(
        range: AnalyticsRange,
        tasks: [AnalyticsTaskRecord],
        taskCategories: [AnalyticsCategoryRecord],
        categoryIDByRootTaskID: [UUID: UUID],
        rangeSegments: [AnalyticsSegmentRecord],
        allSegments: [AnalyticsSegmentRecord],
        sessions: [AnalyticsSessionRecord],
        cancelledPomodoroSessionIDs: Set<UUID>,
        taskPathByID: [UUID: String],
        taskParentPathByID: [UUID: String],
        daily: [DailyAnalyticsPoint],
        period: DateInterval,
        evaluatedAt cutoff: Date,
        calendar: Calendar
    ) -> AnalyticsSnapshot {
        let boundedRangeSegments = boundedSegments(
            rangeSegments,
            in: period,
            now: cutoff
        )
        let focusRoundSegmentIDs = completedFocusRoundSegmentIDs(
            in: allSegments,
            period: period,
            evaluatedAt: cutoff,
            cancelledPomodoroSessionIDs: cancelledPomodoroSessionIDs
        )
        let overview = overview(
            items: boundedRangeSegments,
            completedFocusRoundCount: focusRoundSegmentIDs.count
        )
        let taskBreakdown = taskBreakdown(
            items: boundedRangeSegments,
            tasks: tasks,
            sessions: sessions,
            taskPathByID: taskPathByID
        )
        let comparison = comparison(
            segments: allSegments,
            range: range,
            currentInterval: period,
            evaluatedAt: cutoff,
            calendar: calendar
        )
        let rhythm = rhythm(items: boundedRangeSegments, calendar: calendar)
        let quality = quality(items: boundedRangeSegments)
        let rootBreakdown = rootBreakdown(
            segments: rangeSegments,
            tasks: tasks,
            sessions: sessions,
            taskPathByID: taskPathByID,
            interval: period,
            evaluatedAt: cutoff
        )
        let categoryBreakdown = categoryBreakdown(
            segments: rangeSegments,
            tasks: tasks,
            taskCategories: taskCategories,
            categoryIDByRootTaskID: categoryIDByRootTaskID,
            interval: period,
            evaluatedAt: cutoff
        )
        let todayVisualSnapshot: AnalyticsVisualSnapshot? = if range == .today {
            AnalyticsVisualSnapshotService().snapshot(
                AnalyticsVisualSnapshotInput(
                    range: range,
                    period: period,
                    evaluatedAt: cutoff,
                    calendar: calendar,
                    segments: allSegments,
                    tasks: tasks,
                    sessions: sessions,
                    taskParentPathByID: taskParentPathByID
                )
            )
        } else {
            nil
        }
        return AnalyticsSnapshot(
            range: range,
            overview: overview,
            comparison: comparison,
            rhythm: rhythm,
            quality: quality,
            insights: insights(
                overview: overview,
                comparison: comparison,
                rhythm: rhythm,
                quality: quality,
                taskBreakdown: taskBreakdown
            ),
            daily: daily,
            todayActivity: todayVisualSnapshot?.todayActivity ?? [],
            timeline: todayVisualSnapshot?.timeline ?? .empty,
            completedFocusRoundSegmentIDs: focusRoundSegmentIDs,
            taskBreakdown: taskBreakdown,
            rootBreakdown: rootBreakdown,
            categoryBreakdown: categoryBreakdown,
            overlaps: todayVisualSnapshot?.overlaps ?? overlapSegments(
                items: boundedRangeSegments,
                tasks: tasks,
                sessions: sessions
            )
        )
    }
}
