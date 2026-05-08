import Foundation

extension AnalyticsStore {
    func snapshot(
        range: AnalyticsRange,
        tasks: [TaskNode],
        segments: [TimeSegment],
        sessions: [TimeSession],
        taskPathByID: [UUID: String],
        taskParentPathByID: [UUID: String],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AnalyticsSnapshot {
        PerformanceSignpost.interval("Analytics snapshot generation") {
            let rangeSegments = segmentsForAnalytics(segments, range: range, now: now, calendar: calendar)
            let daily = dailyBreakdown(
                segments: rangeSegments,
                range: range,
                now: now,
                calendar: calendar
            )
            return analyticsSnapshot(
                range: range,
                tasks: tasks,
                rangeSegments: rangeSegments,
                sessions: sessions,
                taskPathByID: taskPathByID,
                taskParentPathByID: taskParentPathByID,
                daily: daily,
                now: now
            )
        }
    }

    mutating func cachedDailySnapshot(
        range: AnalyticsRange,
        tasks: [TaskNode],
        rangeSegments: [TimeSegment],
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
            rangeSegments: rangeSegments,
            sessions: sessions,
            taskPathByID: taskPathByID,
            taskParentPathByID: taskParentPathByID,
            daily: daily,
            now: now
        )
    }

    func analyticsSnapshot(
        range: AnalyticsRange,
        tasks: [TaskNode],
        rangeSegments: [TimeSegment],
        sessions: [TimeSession],
        taskPathByID: [UUID: String],
        taskParentPathByID: [UUID: String],
        daily: [DailyAnalyticsPoint],
        now: Date
    ) -> AnalyticsSnapshot {
        AnalyticsSnapshot(
            range: range,
            overview: overview(segments: rangeSegments, now: now),
            daily: daily,
            taskBreakdown: taskBreakdown(
                segments: rangeSegments,
                tasks: tasks,
                sessions: sessions,
                taskPathByID: taskPathByID,
                taskParentPathByID: taskParentPathByID,
                now: now
            ),
            overlaps: overlapSegments(
                segments: rangeSegments,
                tasks: tasks,
                sessions: sessions,
                now: now
            ),
            rangeSegments: rangeSegments
        )
    }
}
