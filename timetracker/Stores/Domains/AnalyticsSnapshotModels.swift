import Foundation

struct AnalyticsSnapshot {
    let range: AnalyticsRange
    let overview: AnalyticsOverview
    let comparison: AnalyticsComparison
    let rhythm: AnalyticsRhythm
    let quality: AnalyticsQuality
    let insights: [AnalyticsInsight]
    let daily: [DailyAnalyticsPoint]
    let todayActivity: [HourTaskActivity]
    let timeline: AnalyticsTimelineSnapshot
    let taskBreakdown: [TaskAnalyticsPoint]
    let rootBreakdown: [AnalyticsGroupBreakdownPoint]
    let categoryBreakdown: [AnalyticsGroupBreakdownPoint]
    let overlaps: [OverlapAnalyticsPoint]
}
