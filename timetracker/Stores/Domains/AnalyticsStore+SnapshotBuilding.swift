import Foundation

extension AnalyticsStore {
    func snapshot(
        range: AnalyticsRange,
        tasks: [TaskNode],
        taskCategories: [TaskCategory] = [],
        taskCategoryAssignments: [TaskCategoryAssignment] = [],
        segments: [TimeSegment],
        sessions: [TimeSession],
        taskPathByID: [UUID: String],
        taskParentPathByID: [UUID: String],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AnalyticsSnapshot {
        let period = analyticsInterval(for: range, now: now, calendar: calendar)
            ?? DateInterval(start: now, duration: 0)
        return snapshot(
            range: range,
            period: period,
            tasks: tasks,
            taskCategories: taskCategories,
            taskCategoryAssignments: taskCategoryAssignments,
            segments: segments,
            sessions: sessions,
            taskPathByID: taskPathByID,
            taskParentPathByID: taskParentPathByID,
            evaluatedAt: now,
            calendar: calendar
        )
    }

    func snapshot(
        range: AnalyticsRange,
        period: DateInterval,
        tasks: [TaskNode],
        taskCategories: [TaskCategory] = [],
        taskCategoryAssignments: [TaskCategoryAssignment] = [],
        segments: [TimeSegment],
        sessions: [TimeSession],
        taskPathByID: [UUID: String],
        taskParentPathByID: [UUID: String],
        evaluatedAt cutoff: Date,
        calendar: Calendar = .current
    ) -> AnalyticsSnapshot {
        PerformanceSignpost.interval("Analytics snapshot generation") {
            let canonicalSegments = segments.deduplicatedByID()
            let rangeSegments = segmentsForAnalytics(
                canonicalSegments,
                interval: period,
                evaluatedAt: cutoff
            )
            let daily = dailyBreakdown(
                segments: rangeSegments,
                range: range,
                interval: period,
                evaluatedAt: cutoff,
                calendar: calendar
            )
            return analyticsSnapshot(
                range: range,
                tasks: tasks,
                taskCategories: taskCategories,
                taskCategoryAssignments: taskCategoryAssignments,
                rangeSegments: rangeSegments,
                allSegments: canonicalSegments,
                sessions: sessions,
                taskPathByID: taskPathByID,
                taskParentPathByID: taskParentPathByID,
                daily: daily,
                period: period,
                evaluatedAt: cutoff,
                calendar: calendar
            )
        }
    }

    mutating func cachedDailySnapshot(
        range: AnalyticsRange,
        tasks: [TaskNode],
        taskCategories: [TaskCategory],
        taskCategoryAssignments: [TaskCategoryAssignment],
        rangeSegments: [TimeSegment],
        allSegments: [TimeSegment],
        sessions: [TimeSession],
        taskPathByID: [UUID: String],
        taskParentPathByID: [UUID: String],
        period: DateInterval,
        evaluatedAt cutoff: Date,
        calendar: Calendar
    ) -> AnalyticsSnapshot {
        let daily = cachedDailyBreakdown(
            segments: rangeSegments,
            range: range,
            interval: period,
            evaluatedAt: cutoff,
            calendar: calendar
        )
        return analyticsSnapshot(
            range: range,
            tasks: tasks,
            taskCategories: taskCategories,
            taskCategoryAssignments: taskCategoryAssignments,
            rangeSegments: rangeSegments,
            allSegments: allSegments,
            sessions: sessions,
            taskPathByID: taskPathByID,
            taskParentPathByID: taskParentPathByID,
            daily: daily,
            period: period,
            evaluatedAt: cutoff,
            calendar: calendar
        )
    }

    func analyticsSnapshot(
        range: AnalyticsRange,
        tasks: [TaskNode],
        taskCategories: [TaskCategory],
        taskCategoryAssignments: [TaskCategoryAssignment],
        rangeSegments: [TimeSegment],
        allSegments: [TimeSegment],
        sessions: [TimeSession],
        taskPathByID: [UUID: String],
        taskParentPathByID: [UUID: String],
        daily: [DailyAnalyticsPoint],
        period: DateInterval,
        evaluatedAt cutoff: Date,
        calendar: Calendar
    ) -> AnalyticsSnapshot {
        let boundedRangeSegments = boundedSegments(
            rangeSegments.deduplicatedByID(),
            in: period,
            now: cutoff
        )
        let overview = overview(items: boundedRangeSegments)
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
        let rhythm = rhythm(
            segments: rangeSegments,
            interval: period,
            taskIDs: nil,
            now: cutoff,
            calendar: calendar
        )
        let quality = quality(
            segments: rangeSegments,
            interval: period,
            taskIDs: nil,
            now: cutoff
        )
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
            taskCategoryAssignments: taskCategoryAssignments,
            interval: period,
            evaluatedAt: cutoff
        )
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
            todayActivity: range == .today
                ? HourTaskActivityService().hourlyActivity(
                    segments: rangeSegments,
                    tasks: tasks,
                    sessions: sessions,
                    date: period.start,
                    now: cutoff,
                    calendar: calendar
                )
                : [],
            timeline: range == .today
                ? AnalyticsTimelineSnapshotService().snapshot(
                    segments: rangeSegments,
                    tasks: tasks,
                    sessions: sessions,
                    taskParentPathByID: taskParentPathByID,
                    date: period.start,
                    now: cutoff,
                    calendar: calendar
                )
                : .empty,
            taskBreakdown: taskBreakdown,
            rootBreakdown: rootBreakdown,
            categoryBreakdown: categoryBreakdown,
            overlaps: overlapSegments(
                items: boundedRangeSegments,
                tasks: tasks,
                sessions: sessions
            )
        )
    }
}
