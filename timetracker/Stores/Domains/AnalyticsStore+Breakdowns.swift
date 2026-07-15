import Foundation

extension AnalyticsStore {
    func overview(items: [AnalyticsBoundedSegment]) -> AnalyticsOverview {
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
            pomodoroCount: focusItems.filter { item in
                guard let endedAt = item.segment.endedAt else { return false }
                return endedAt > item.interval.start && endedAt <= item.interval.end
            }.count,
            averageFocusSeconds: focusItems.isEmpty ? 0 : focusSeconds / focusItems.count
        )
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

    func taskBreakdown(
        items: [AnalyticsBoundedSegment],
        tasks: [TaskNode],
        sessions: [TimeSession],
        taskPathByID: [UUID: String]
    ) -> [TaskAnalyticsPoint] {
        let taskByID = tasks.latestByID()
        let sessionsByTaskID = Dictionary(grouping: sessions.deduplicatedByID(), by: \.taskID)
        let grouped = Dictionary(grouping: items) { $0.segment.taskID }

        return grouped.compactMap { taskID, taskItems -> TaskAnalyticsPoint? in
            let gross = taskItems.reduce(0) { $0 + $1.durationSeconds }
            guard gross > 0 else { return nil }

            let task = taskByID[taskID]
            let fallbackTitle = sessionsByTaskID[taskID]?.first?.titleSnapshot ?? AppStrings.localized("task.deleted")
            return TaskAnalyticsPoint(
                taskID: taskID,
                title: task?.title ?? fallbackTitle,
                path: task.map { taskPathByID[$0.id] ?? $0.title } ?? AppStrings.localized("task.deleted.path"),
                colorHex: task?.colorHex,
                iconName: task?.iconName,
                status: task?.status,
                grossSeconds: gross,
                wallSeconds: TimeAggregationService().mergeOverlappingIntervals(taskItems.map(\.interval)).reduce(0) {
                    $0 + Int($1.end.timeIntervalSince($1.start))
                }
            )
        }
        .sorted { $0.grossSeconds > $1.grossSeconds }
    }

    func analyticsInterval(for range: AnalyticsRange, now: Date, calendar: Calendar) -> DateInterval? {
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
