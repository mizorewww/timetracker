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
        PerformanceSignpost.interval("Analytics snapshot generation") {
            let canonicalSegments = segments.deduplicatedByID()
            let rangeSegments = segmentsForAnalytics(
                canonicalSegments,
                range: range,
                now: now,
                calendar: calendar
            )
            let daily = dailyBreakdown(
                segments: rangeSegments,
                range: range,
                now: now,
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
                now: now,
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
        now: Date,
        calendar: Calendar
    ) -> AnalyticsSnapshot {
        let daily = cachedDailyBreakdown(segments: rangeSegments, range: range, now: now, calendar: calendar)
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
            now: now,
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
        now: Date,
        calendar: Calendar
    ) -> AnalyticsSnapshot {
        let boundedRangeSegments = analyticsInterval(for: range, now: now, calendar: calendar).map {
            boundedSegments(rangeSegments.deduplicatedByID(), in: $0, now: now)
        } ?? []
        let overview = overview(items: boundedRangeSegments)
        let taskBreakdown = taskBreakdown(
            items: boundedRangeSegments,
            tasks: tasks,
            sessions: sessions,
            taskPathByID: taskPathByID
        )
        let comparison = comparison(segments: allSegments, range: range, now: now, calendar: calendar)
        let rhythm = rhythm(segments: rangeSegments, range: range, now: now, calendar: calendar)
        let quality = quality(segments: rangeSegments, range: range, now: now, calendar: calendar)
        let rootBreakdown = rootBreakdown(
            segments: rangeSegments,
            tasks: tasks,
            sessions: sessions,
            taskPathByID: taskPathByID,
            range: range,
            now: now,
            calendar: calendar
        )
        let categoryBreakdown = categoryBreakdown(
            segments: rangeSegments,
            tasks: tasks,
            taskCategories: taskCategories,
            taskCategoryAssignments: taskCategoryAssignments,
            range: range,
            now: now,
            calendar: calendar
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
                    date: now,
                    now: now,
                    calendar: calendar
                )
                : [],
            timeline: range == .today
                ? AnalyticsTimelineSnapshotService().snapshot(
                    segments: rangeSegments,
                    tasks: tasks,
                    sessions: sessions,
                    taskParentPathByID: taskParentPathByID,
                    date: now,
                    now: now,
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
            ),
            rangeSegments: rangeSegments
        )
    }
}
