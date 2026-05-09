import Foundation

struct AnalyticsSnapshot {
    let range: AnalyticsRange
    let overview: AnalyticsOverview
    let daily: [DailyAnalyticsPoint]
    let todayActivity: [HourTaskActivity]
    let timeline: AnalyticsTimelineSnapshot
    let taskBreakdown: [TaskAnalyticsPoint]
    let overlaps: [OverlapAnalyticsPoint]
    let rangeSegments: [TimeSegment]
}
