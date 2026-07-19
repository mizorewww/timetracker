import Foundation

struct HomeWeeklyGrossTimeRefreshRequest: Hashable {
    let evaluationKey: AnalyticsEvaluationCacheKey
    let analyticsRevision: UInt
    let clockRevision: UInt

    @MainActor
    init(
        store: TimeTrackerStore,
        snapshot: WeeklyGrossTimeSnapshot?,
        now: Date,
        clockRevision: UInt,
        calendar: Calendar
    ) {
        let evaluation = AnalyticsRange.week.evaluation(
            referenceDate: now,
            liveNow: now,
            calendar: calendar
        )
        let needsLiveRefresh = store.activeSegments.isEmpty == false ||
            snapshot?.requiresLiveRefresh == true
        let liveRefreshBucket = needsLiveRefresh
            ? Int(now.timeIntervalSinceReferenceDate / 60)
            : nil
        evaluationKey = AnalyticsEvaluationCacheKey(
            evaluation: evaluation,
            liveRefreshBucket: liveRefreshBucket,
            calendar: calendar
        )
        analyticsRevision = store.analyticsRevision
        self.clockRevision = clockRevision
    }
}
