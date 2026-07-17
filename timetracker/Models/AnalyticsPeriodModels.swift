import Foundation

enum AnalyticsRange: String, CaseIterable, Identifiable, Sendable {
    case today = "Today"
    case week = "Week"
    case month = "Month"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .today:
            return AppStrings.localized("analytics.range.day")
        case .week:
            return AppStrings.localized("analytics.range.week")
        case .month:
            return AppStrings.localized("analytics.range.month")
        }
    }
}

/// Separates the selected calendar period from the two notions of "now" used
/// while evaluating it. `cutoff` clips tracked time, while `clockReference`
/// is the actual wall clock used to detect a genuine system-clock rewind.
nonisolated struct AnalyticsPeriodEvaluation: Hashable, Sendable {
    let interval: DateInterval
    let cutoff: Date
    let clockReference: Date
}

/// Shared identity for view requests and domain caches. Current week/month
/// snapshots advance at local midnight even when no active timer creates a
/// minute bucket; completed and future periods remain stable.
nonisolated struct AnalyticsEvaluationCacheKey: Hashable, Sendable {
    let intervalStart: Date
    let intervalEnd: Date
    let liveDayStart: Date?
    let liveRefreshBucket: Int?

    init(
        evaluation: AnalyticsPeriodEvaluation,
        liveRefreshBucket: Int?,
        calendar: Calendar = .current
    ) {
        self.init(
            interval: evaluation.interval,
            clockReference: evaluation.clockReference,
            liveRefreshBucket: liveRefreshBucket,
            calendar: calendar
        )
    }

    init(
        interval: DateInterval,
        clockReference: Date,
        liveRefreshBucket: Int?,
        calendar: Calendar = .current
    ) {
        intervalStart = interval.start
        intervalEnd = interval.end
        liveDayStart = interval.contains(clockReference)
            ? calendar.dateInterval(of: .day, for: clockReference)?.start
            : nil
        self.liveRefreshBucket = liveRefreshBucket
    }

    var interval: DateInterval {
        DateInterval(start: intervalStart, end: intervalEnd)
    }
}

nonisolated extension AnalyticsRange {
    func interval(
        containing date: Date,
        calendar: Calendar = .current
    ) -> DateInterval? {
        switch self {
        case .today:
            return calendar.dateInterval(of: .day, for: date)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)
        case .month:
            return calendar.dateInterval(of: .month, for: date)
        }
    }

    func evaluation(
        referenceDate: Date,
        liveNow: Date,
        calendar: Calendar = .current
    ) -> AnalyticsPeriodEvaluation {
        let selectedInterval = interval(containing: referenceDate, calendar: calendar)
            ?? DateInterval(start: referenceDate, duration: 0)
        let cutoff: Date
        if selectedInterval.contains(liveNow) {
            cutoff = liveNow
        } else if selectedInterval.end <= liveNow {
            // DateInterval is half-open. Evaluating a completed period exactly
            // at its end preserves every instant before the boundary.
            cutoff = selectedInterval.end
        } else {
            // A future period must remain empty until its start arrives.
            cutoff = selectedInterval.start
        }
        return AnalyticsPeriodEvaluation(
            interval: selectedInterval,
            cutoff: cutoff,
            clockReference: liveNow
        )
    }

    func isCurrentPeriod(
        _ date: Date,
        liveNow: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard let selected = interval(containing: date, calendar: calendar),
              let current = interval(containing: liveNow, calendar: calendar) else {
            return false
        }
        return selected.start == current.start
    }

    func date(
        byAdding value: Int,
        to date: Date,
        calendar: Calendar = .current
    ) -> Date? {
        switch self {
        case .today:
            return calendar.date(byAdding: .day, value: value, to: date)
        case .week:
            return calendar.date(byAdding: .weekOfYear, value: value, to: date)
        case .month:
            // Month identity moves from its canonical boundary. Navigation
            // reapplies the user's independent day/time anchor afterward.
            guard let monthStart = interval(
                containing: date,
                calendar: calendar
            )?.start else {
                return nil
            }
            return calendar.date(byAdding: .month, value: value, to: monthStart)
        }
    }
}

nonisolated enum AnalyticsComparisonBasis: Equatable, Sendable {
    case matchedProgress
    case completePeriods
}

/// The exact calendar windows used by a comparison. A live or future period
/// compares only matching progress; a completed historical period compares the
/// two complete periods.
nonisolated struct AnalyticsComparisonWindow: Equatable, Sendable {
    let current: DateInterval
    let previous: DateInterval
    let basis: AnalyticsComparisonBasis
}
