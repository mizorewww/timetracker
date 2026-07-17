import Foundation

extension AnalyticsStore {
    func previousDecisionInterval(
        for range: AnalyticsRange,
        currentInterval: DateInterval,
        calendar: Calendar
    ) -> DateInterval? {
        let component: Calendar.Component
        switch range {
        case .today:
            component = .day
        case .week:
            component = .weekOfYear
        case .month:
            component = .month
        }
        guard let previousStart = calendar.date(
            byAdding: component,
            value: -1,
            to: currentInterval.start
        ) else {
            return nil
        }
        return DateInterval(start: previousStart, end: currentInterval.start)
    }

    func comparisonWindow(
        for range: AnalyticsRange,
        currentInterval: DateInterval,
        evaluatedAt cutoff: Date,
        calendar: Calendar
    ) -> AnalyticsComparisonWindow? {
        guard let previousInterval = previousDecisionInterval(
            for: range,
            currentInterval: currentInterval,
            calendar: calendar
        ) else {
            return nil
        }

        let currentEnd = min(max(cutoff, currentInterval.start), currentInterval.end)
        if currentEnd == currentInterval.end {
            return AnalyticsComparisonWindow(
                current: currentInterval,
                previous: previousInterval,
                basis: .completePeriods
            )
        }

        let previousEnd = matchedComparisonEnd(
            currentEnd: currentEnd,
            currentStart: currentInterval.start,
            previousInterval: previousInterval,
            calendar: calendar
        )
        return AnalyticsComparisonWindow(
            current: DateInterval(start: currentInterval.start, end: currentEnd),
            previous: DateInterval(start: previousInterval.start, end: previousEnd),
            basis: .matchedProgress
        )
    }

    /// Maps progress by calendar-day ordinal and local wall-clock components.
    /// This preserves noon across DST transitions and clamps a day that does
    /// not exist in a shorter previous month to that period's end.
    private func matchedComparisonEnd(
        currentEnd: Date,
        currentStart: Date,
        previousInterval: DateInterval,
        calendar: Calendar
    ) -> Date {
        let currentStartOfDay = calendar.startOfDay(for: currentStart)
        let currentEndStartOfDay = calendar.startOfDay(for: currentEnd)
        let dayOffset = max(
            0,
            calendar.dateComponents(
                [.day],
                from: currentStartOfDay,
                to: currentEndStartOfDay
            ).day ?? 0
        )
        guard let previousDay = calendar.date(
            byAdding: .day,
            value: dayOffset,
            to: previousInterval.start
        ) else {
            return previousInterval.start
        }

        let clock = calendar.dateComponents(
            [.hour, .minute, .second, .nanosecond],
            from: currentEnd
        )
        guard let matchedSecond = calendar.date(
            bySettingHour: clock.hour ?? 0,
            minute: clock.minute ?? 0,
            second: clock.second ?? 0,
            of: previousDay
        ) else {
            return previousInterval.start
        }
        let matched = matchedSecond.addingTimeInterval(
            Double(clock.nanosecond ?? 0) / 1_000_000_000
        )
        return min(max(matched, previousInterval.start), previousInterval.end)
    }
}
