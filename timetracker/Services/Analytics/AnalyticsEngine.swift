import Foundation

struct AnalyticsEngine {
    private let aggregationService = TimeAggregationService()
    private let dailySummaryService = DailySummaryService()

    func overview(segments: [TimeSegment], range: AnalyticsRange, now: Date = Date(), calendar: Calendar = .current) -> AnalyticsOverview {
        guard let interval = analyticsInterval(for: range, now: now, calendar: calendar) else {
            return AnalyticsOverview(grossSeconds: 0, wallSeconds: 0, overlapSeconds: 0, pomodoroCount: 0, averageFocusSeconds: 0)
        }
        let bounded = segments.compactMap { segment -> (segment: TimeSegment, interval: DateInterval)? in
            guard let clipped = clippedInterval(for: segment, in: interval, now: now) else { return nil }
            return (segment, clipped)
        }
        let gross = bounded.reduce(0) { $0 + Int($1.interval.duration) }
        let wall = aggregationService.mergeOverlappingIntervals(bounded.map { $0.interval }).reduce(0) {
            $0 + Int($1.duration)
        }
        let focusSegments = bounded.filter { $0.segment.source == .pomodoro }
        let focusSeconds = focusSegments.reduce(0) { $0 + Int($1.interval.duration) }

        return AnalyticsOverview(
            grossSeconds: gross,
            wallSeconds: wall,
            overlapSeconds: max(0, gross - wall),
            pomodoroCount: focusSegments.filter { item in
                guard let endedAt = item.segment.endedAt else { return false }
                return endedAt <= now &&
                    endedAt > item.interval.start &&
                    endedAt <= item.interval.end
            }.count,
            averageFocusSeconds: focusSegments.isEmpty ? 0 : focusSeconds / focusSegments.count
        )
    }

    func dailyBreakdown(segments: [TimeSegment], range: AnalyticsRange, now: Date = Date(), calendar: Calendar = .current) -> [DailyAnalyticsPoint] {
        guard let interval = analyticsInterval(for: range, now: now, calendar: calendar) else { return [] }
        let summaries = dailySummaryService.summaries(
            segments: segments,
            interval: interval,
            now: now,
            calendar: calendar
        )
        return dailySummaryService.visibleSummaries(
            summaries,
            interval: interval,
            evaluatedAt: now
        ).map { summary in
            return DailyAnalyticsPoint(
                date: summary.date,
                grossSeconds: summary.grossSeconds,
                wallSeconds: summary.wallClockSeconds,
                label: dayLabel(for: summary.date, range: range, calendar: calendar)
            )
        }
    }

    func hourlyBreakdown(segments: [TimeSegment], date: Date = Date(), now: Date = Date(), calendar: Calendar = .current) -> [HourlyAnalyticsPoint] {
        let startOfDay = calendar.startOfDay(for: date)
        let dayInterval = calendar.dateInterval(of: .day, for: date)
            ?? DateInterval(start: startOfDay, duration: 86_400)
        let buckets = hourlyBuckets(segments: segments, dayInterval: dayInterval, now: now, calendar: calendar)

        return (0..<24).map { hour in
            let bucket = buckets[hour]
            let wall = aggregationService.mergeOverlappingIntervals(bucket.wallIntervals).reduce(0) {
                $0 + Int($1.end.timeIntervalSince($1.start))
            }
            return HourlyAnalyticsPoint(hour: hour, grossSeconds: bucket.grossSeconds, wallSeconds: wall)
        }
    }

    private func analyticsInterval(for range: AnalyticsRange, now: Date, calendar: Calendar) -> DateInterval? {
        switch range {
        case .today:
            return calendar.dateInterval(of: .day, for: now)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: now)
        case .month:
            return calendar.dateInterval(of: .month, for: now)
        }
    }

    private func dayLabel(for date: Date, range: AnalyticsRange, calendar: Calendar) -> String {
        switch range {
        case .today:
            return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
        case .week:
            let weekday = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
            return "\(weekday) \(calendar.component(.day, from: date))"
        case .month:
            return "\(calendar.component(.day, from: date))"
        }
    }

    private func clippedInterval(for segment: TimeSegment, in interval: DateInterval, now: Date) -> DateInterval? {
        guard segment.deletedAt == nil else { return nil }
        return TrackedTimePolicy.interval(
            startedAt: segment.startedAt,
            endedAt: segment.endedAt,
            now: now,
            clippedTo: interval
        )
    }

    private func hourlyBuckets(
        segments: [TimeSegment],
        dayInterval: DateInterval,
        now: Date,
        calendar: Calendar
    ) -> [HourlyAnalyticsBucket] {
        var buckets = Array(repeating: HourlyAnalyticsBucket(), count: 24)

        for segment in segments {
            guard let clipped = clippedInterval(for: segment, in: dayInterval, now: now) else { continue }
            distribute(clipped, into: &buckets, calendar: calendar)
        }

        return buckets
    }

    private func distribute(
        _ interval: DateInterval,
        into buckets: inout [HourlyAnalyticsBucket],
        calendar: Calendar
    ) {
        var cursor = interval.start
        while cursor < interval.end {
            let hour = calendar.component(.hour, from: cursor)
            let nextHour = calendar.dateInterval(of: .hour, for: cursor)?.end ?? interval.end
            let end = min(nextHour, interval.end)
            guard end > cursor else { break }
            if (0..<24).contains(hour) {
                let clipped = DateInterval(start: cursor, end: end)
                buckets[hour].grossSeconds += max(0, Int(end.timeIntervalSince(cursor)))
                buckets[hour].wallIntervals.append(clipped)
            }
            cursor = end
        }
    }
}

private struct HourlyAnalyticsBucket {
    var grossSeconds: Int = 0
    var wallIntervals: [DateInterval] = []
}
