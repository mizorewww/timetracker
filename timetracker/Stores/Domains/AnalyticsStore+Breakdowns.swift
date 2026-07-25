import Foundation

extension AnalyticsStore {
    func overview(
        items: [AnalyticsBoundedSegment],
        completedFocusRoundCount: Int? = nil
    ) -> AnalyticsOverview {
        let gross = items.reduce(0) { $0 + $1.durationSeconds }
        let intervals = items.map(\.interval)
        let wall = TimeAggregationService().mergeOverlappingIntervals(intervals).reduce(0) {
            $0 + Int($1.end.timeIntervalSince($1.start))
        }
        let focusItems = items.filter { $0.segment.source == .pomodoro }
        let focusSeconds = focusItems.reduce(0) { $0 + $1.durationSeconds }

        return AnalyticsOverview(
            grossSeconds: gross,
            wallSeconds: wall,
            overlapSeconds: max(0, gross - wall),
            pomodoroCount: completedFocusRoundCount ?? focusItems.filter { item in
                guard let endedAt = item.segment.endedAt else { return false }
                return endedAt > item.interval.start && endedAt <= item.interval.end
            }.count,
            averageFocusSeconds: focusItems.isEmpty ? 0 : focusSeconds / focusItems.count
        )
    }

    /// Focus-round completion is an event, so an event exactly at the selected
    /// period's start belongs to that period even if the segment's duration
    /// clips to zero there.
    func completedFocusRoundSegmentIDs(
        in segments: [TimeSegment],
        period: DateInterval,
        evaluatedAt cutoff: Date,
        cancelledPomodoroSessionIDs: Set<UUID> = []
    ) -> [UUID] {
        segments.filter { segment in
            AnalyticsFocusRoundPolicy.isCompleted(
                segment: segment,
                period: period,
                evaluatedAt: cutoff,
                cancelledPomodoroSessionIDs: cancelledPomodoroSessionIDs
            )
        }
        .sorted { lhs, rhs in
            let lhsEnd = lhs.endedAt ?? period.start
            let rhsEnd = rhs.endedAt ?? period.start
            if lhsEnd != rhsEnd {
                return lhsEnd > rhsEnd
            }
            if lhs.startedAt != rhs.startedAt {
                return lhs.startedAt > rhs.startedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        .map(\.id)
    }

    func boundedSegments(
        _ segments: [TimeSegment],
        in interval: DateInterval,
        taskIDs: Set<UUID>? = nil,
        now: Date
    ) -> [AnalyticsBoundedSegment] {
        segments.compactMap { segment in
            guard segment.deletedAt == nil else { return nil }
            if let taskIDs, !taskIDs.contains(segment.taskID) {
                return nil
            }
            guard let clipped = TrackedTimePolicy.interval(
                startedAt: segment.startedAt,
                endedAt: segment.endedAt,
                now: now,
                clippedTo: interval
            ) else {
                return nil
            }
            return AnalyticsBoundedSegment(
                segment: segment,
                interval: clipped
            )
        }
    }

    func dailyBreakdown(
        segments: [TimeSegment],
        range: AnalyticsRange,
        now: Date,
        calendar: Calendar
    ) -> [DailyAnalyticsPoint] {
        guard let interval = analyticsInterval(for: range, now: now, calendar: calendar) else { return [] }
        return dailyBreakdown(
            segments: segments,
            range: range,
            interval: interval,
            evaluatedAt: now,
            calendar: calendar
        )
    }

    func dailyBreakdown(
        segments: [TimeSegment],
        range: AnalyticsRange,
        interval: DateInterval,
        evaluatedAt cutoff: Date,
        calendar: Calendar
    ) -> [DailyAnalyticsPoint] {
        let summaryService = DailySummaryService()
        let summaries = summaryService.summaries(
            segments: segments,
            interval: interval,
            now: cutoff,
            calendar: calendar
        )
        return summaryService.visibleSummaries(
            summaries,
            interval: interval,
            evaluatedAt: cutoff
        ).map { summary in
            DailyAnalyticsPoint(
                date: summary.date,
                grossSeconds: summary.grossSeconds,
                wallSeconds: summary.wallClockSeconds,
                label: dayLabel(for: summary.date, range: range, calendar: calendar)
            )
        }
    }

    mutating func cachedDailyBreakdown(
        segments: [TimeSegment],
        range: AnalyticsRange,
        now: Date,
        calendar: Calendar
    ) -> [DailyAnalyticsPoint] {
        guard let interval = analyticsInterval(for: range, now: now, calendar: calendar) else { return [] }
        return cachedDailyBreakdown(
            segments: segments,
            range: range,
            interval: interval,
            evaluatedAt: now,
            calendar: calendar
        )
    }

    mutating func cachedDailyBreakdown(
        segments: [TimeSegment],
        range: AnalyticsRange,
        interval: DateInterval,
        evaluatedAt cutoff: Date,
        calendar: Calendar
    ) -> [DailyAnalyticsPoint] {
        let summaries = ledgerBucketCache.summaries(
            segments: segments,
            interval: interval,
            now: cutoff,
            calendar: calendar
        )
        return DailySummaryService().visibleSummaries(
            summaries,
            interval: interval,
            evaluatedAt: cutoff
        ).map { summary in
            DailyAnalyticsPoint(
                date: summary.date,
                grossSeconds: summary.grossSeconds,
                wallSeconds: summary.wallClockSeconds,
                label: dayLabel(for: summary.date, range: range, calendar: calendar)
            )
        }
    }

    func segmentsForAnalytics(_ segments: [TimeSegment], range: AnalyticsRange, now: Date, calendar: Calendar) -> [TimeSegment] {
        guard let interval = analyticsInterval(for: range, now: now, calendar: calendar) else { return segments }
        return segmentsForAnalytics(segments, interval: interval, evaluatedAt: now)
    }

    func segmentsForAnalytics(
        _ segments: [TimeSegment],
        interval: DateInterval,
        evaluatedAt cutoff: Date
    ) -> [TimeSegment] {
        segments.filter { overlaps($0, interval: interval, now: cutoff) }
    }

    func analyticsInterval(for range: AnalyticsRange, now: Date, calendar: Calendar) -> DateInterval? {
        switch range {
        case .today:
            calendar.dateInterval(of: .day, for: now)
        case .week:
            calendar.dateInterval(of: .weekOfYear, for: now)
        case .month:
            calendar.dateInterval(of: .month, for: now)
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

    private func overlaps(_ segment: TimeSegment, interval: DateInterval, now: Date) -> Bool {
        segment.deletedAt == nil && TrackedTimePolicy.overlaps(
            startedAt: segment.startedAt,
            endedAt: segment.endedAt,
            interval: interval,
            now: now
        )
    }
}

struct AnalyticsBoundedSegment {
    let segment: TimeSegment
    let interval: DateInterval

    var durationSeconds: Int {
        max(0, Int(interval.end.timeIntervalSince(interval.start)))
    }
}

enum AnalyticsFocusRoundPolicy {
    static func isCompleted(
        segment: TimeSegment,
        period: DateInterval,
        evaluatedAt cutoff: Date,
        cancelledPomodoroSessionIDs: Set<UUID>
    ) -> Bool {
        guard segment.deletedAt == nil,
              segment.source == .pomodoro,
              cancelledPomodoroSessionIDs.contains(segment.sessionID) == false,
              let endedAt = segment.endedAt,
              endedAt > segment.startedAt
        else {
            return false
        }
        return endedAt >= period.start &&
            endedAt < period.end &&
            endedAt <= cutoff
    }
}
