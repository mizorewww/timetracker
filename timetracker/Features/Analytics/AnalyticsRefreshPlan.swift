import Foundation

nonisolated struct AnalyticsRefreshPlan: Hashable, Sendable {
    nonisolated enum Reason: Hashable, Sendable {
        case liveMinute
        case nextLocalDay
    }

    /// The wall-clock sample that created this plan. Keeping it in the task identity
    /// forces a reschedule when the system clock moves within the same minute bucket.
    let scheduledAt: Date
    let deadline: Date
    let reason: Reason

    static func next(
        liveNow: Date,
        followsCurrentPeriod: Bool,
        liveRefreshBucket: Int?,
        calendar: Calendar = .current
    ) -> AnalyticsRefreshPlan? {
        guard followsCurrentPeriod else { return nil }

        if let liveRefreshBucket {
            let bucketDeadline = Date(
                timeIntervalSinceReferenceDate: TimeInterval(liveRefreshBucket + 1) * 60
            )
            if bucketDeadline > liveNow {
                return AnalyticsRefreshPlan(
                    scheduledAt: liveNow,
                    deadline: bucketDeadline,
                    reason: .liveMinute
                )
            }

            let currentBucket = floor(liveNow.timeIntervalSinceReferenceDate / 60)
            return AnalyticsRefreshPlan(
                scheduledAt: liveNow,
                deadline: Date(timeIntervalSinceReferenceDate: (currentBucket + 1) * 60),
                reason: .liveMinute
            )
        }

        guard let nextLocalDay = calendar.dateInterval(of: .day, for: liveNow)?.end,
              nextLocalDay > liveNow else {
            return nil
        }
        return AnalyticsRefreshPlan(
            scheduledAt: liveNow,
            deadline: nextLocalDay,
            reason: .nextLocalDay
        )
    }
}
