import Foundation

struct AnalyticsEngine {
    private let aggregationService = TimeAggregationService()

    func overview(segments: [TimeSegment], range: AnalyticsRange, now: Date = Date(), calendar: Calendar = .current) -> AnalyticsOverview {
        let rangeSegments = segmentsForAnalytics(segments, range: range, now: now, calendar: calendar)
        let gross = aggregationService.totalSeconds(segments: rangeSegments, mode: .gross, now: now)
        let wall = aggregationService.totalSeconds(segments: rangeSegments, mode: .wallClock, now: now)
        let focusSegments = rangeSegments.filter { $0.source == .pomodoro }
        let averageFocus = focusSegments.isEmpty ? 0 : aggregationService.grossSeconds(focusSegments, now: now) / focusSegments.count

        return AnalyticsOverview(
            grossSeconds: gross,
            wallSeconds: wall,
            overlapSeconds: max(0, gross - wall),
            pomodoroCount: focusSegments.filter { $0.endedAt != nil }.count,
            averageFocusSeconds: averageFocus
        )
    }

    func dailyBreakdown(segments: [TimeSegment], range: AnalyticsRange, now: Date = Date(), calendar: Calendar = .current) -> [DailyAnalyticsPoint] {
        dayIntervals(for: range, now: now, calendar: calendar).map { interval in
            let daySegments = segments.filter { overlaps($0, interval: interval, now: now) }
            return DailyAnalyticsPoint(
                date: interval.start,
                grossSeconds: aggregationService.totalSeconds(segments: daySegments, mode: .gross, now: now),
                wallSeconds: aggregationService.totalSeconds(segments: daySegments, mode: .wallClock, now: now),
                label: dayLabel(for: interval.start, range: range, calendar: calendar)
            )
        }
    }

    func hourlyBreakdown(segments: [TimeSegment], date: Date = Date(), now: Date = Date(), calendar: Calendar = .current) -> [HourlyAnalyticsPoint] {
        let startOfDay = calendar.startOfDay(for: date)
        return (0..<24).map { hour in
            let start = calendar.date(byAdding: .hour, value: hour, to: startOfDay) ?? startOfDay
            let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3_600)
            let interval = DateInterval(start: start, end: end)
            let hourSegments = segments.filter { overlaps($0, interval: interval, now: now) }
            let gross = secondsOverlapping(segments: hourSegments, interval: interval, now: now)
            let wallIntervals = hourSegments.compactMap { clippedInterval(for: $0, in: interval, now: now) }
            let wall = aggregationService.mergeOverlappingIntervals(wallIntervals).reduce(0) {
                $0 + Int($1.end.timeIntervalSince($1.start))
            }
            return HourlyAnalyticsPoint(hour: hour, grossSeconds: gross, wallSeconds: wall)
        }
    }

    private func segmentsForAnalytics(_ segments: [TimeSegment], range: AnalyticsRange, now: Date, calendar: Calendar) -> [TimeSegment] {
        guard let interval = analyticsInterval(for: range, now: now, calendar: calendar) else { return segments }
        return segments.filter { overlaps($0, interval: interval, now: now) }
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

    private func dayIntervals(for range: AnalyticsRange, now: Date, calendar: Calendar) -> [DateInterval] {
        guard let interval = analyticsInterval(for: range, now: now, calendar: calendar) else { return [] }
        var result: [DateInterval] = []
        var cursor = interval.start
        while cursor < interval.end {
            let next = calendar.date(byAdding: .day, value: 1, to: cursor) ?? interval.end
            result.append(DateInterval(start: cursor, end: min(next, interval.end)))
            cursor = next
        }
        return result
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

    private func overlaps(_ segment: TimeSegment, interval: DateInterval, now: Date) -> Bool {
        let end = segment.endedAt ?? now
        return segment.deletedAt == nil && segment.startedAt < interval.end && end > interval.start
    }

    private func clippedInterval(for segment: TimeSegment, in interval: DateInterval, now: Date) -> DateInterval? {
        guard segment.deletedAt == nil else { return nil }
        let end = segment.endedAt ?? now
        let start = max(segment.startedAt, interval.start)
        let clippedEnd = min(end, interval.end)
        guard clippedEnd > start else { return nil }
        return DateInterval(start: start, end: clippedEnd)
    }

    private func secondsOverlapping(segments: [TimeSegment], interval: DateInterval, now: Date) -> Int {
        segments.reduce(0) { result, segment in
            guard let clipped = clippedInterval(for: segment, in: interval, now: now) else { return result }
            return result + Int(clipped.end.timeIntervalSince(clipped.start))
        }
    }
}
