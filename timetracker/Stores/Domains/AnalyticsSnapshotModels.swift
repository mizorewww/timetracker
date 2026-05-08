import Foundation

struct AnalyticsSnapshot {
    let range: AnalyticsRange
    let overview: AnalyticsOverview
    let daily: [DailyAnalyticsPoint]
    let taskBreakdown: [TaskAnalyticsPoint]
    let overlaps: [OverlapAnalyticsPoint]
    let rangeSegments: [TimeSegment]
}
