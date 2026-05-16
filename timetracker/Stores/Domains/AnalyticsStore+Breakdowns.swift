import Foundation

extension AnalyticsStore {
    func overview(segments: [TimeSegment], now: Date) -> AnalyticsOverview {
        let aggregationService = TimeAggregationService()
        let gross = aggregationService.totalSeconds(segments: segments, mode: .gross, now: now)
        let wall = aggregationService.totalSeconds(segments: segments, mode: .wallClock, now: now)
        let focusSegments = segments.filter { $0.source == .pomodoro }
        let averageFocus = focusSegments.isEmpty ? 0 : aggregationService.grossSeconds(focusSegments, now: now) / focusSegments.count

        return AnalyticsOverview(
            grossSeconds: gross,
            wallSeconds: wall,
            overlapSeconds: max(0, gross - wall),
            pomodoroCount: focusSegments.filter { $0.endedAt != nil }.count,
            averageFocusSeconds: averageFocus
        )
    }

    func dailyBreakdown(
        segments: [TimeSegment],
        range: AnalyticsRange,
        now: Date,
        calendar: Calendar
    ) -> [DailyAnalyticsPoint] {
        guard let interval = analyticsInterval(for: range, now: now, calendar: calendar) else { return [] }
        return DailySummaryService().summaries(segments: segments, interval: interval, now: now, calendar: calendar).map { summary in
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
        return ledgerBucketCache.summaries(segments: segments, interval: interval, now: now, calendar: calendar).map { summary in
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
        return segments.filter { overlaps($0, interval: interval, now: now) }
    }

    func taskBreakdown(
        segments: [TimeSegment],
        tasks: [TaskNode],
        sessions: [TimeSession],
        taskPathByID: [UUID: String],
        taskParentPathByID: [UUID: String],
        now: Date
    ) -> [TaskAnalyticsPoint] {
        let aggregationService = TimeAggregationService()
        let taskByID = tasks.latestByID()
        let sessionsByTaskID = Dictionary(grouping: sessions.deduplicatedByID(), by: \.taskID)
        let grouped = Dictionary(grouping: segments.deduplicatedByID(), by: \.taskID)

        return grouped.compactMap { taskID, taskSegments -> TaskAnalyticsPoint? in
            let gross = aggregationService.totalSeconds(segments: taskSegments, mode: .gross, now: now)
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
                wallSeconds: aggregationService.totalSeconds(segments: taskSegments, mode: .wallClock, now: now)
            )
        }
        .sorted { $0.grossSeconds > $1.grossSeconds }
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

    private func overlaps(_ segment: TimeSegment, interval: DateInterval, now: Date) -> Bool {
        let end = segment.endedAt ?? now
        return segment.deletedAt == nil && segment.startedAt < interval.end && end > interval.start
    }
}
