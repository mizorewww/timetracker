import Foundation

struct AnalyticsSnapshot {
    let range: AnalyticsRange
    let overview: AnalyticsOverview
    let daily: [DailyAnalyticsPoint]
    let taskBreakdown: [TaskAnalyticsPoint]
    let overlaps: [OverlapAnalyticsPoint]
    let rangeSegments: [TimeSegment]
}

struct AnalyticsStore {
    private struct BoundedOverlapSegment {
        let segment: TimeSegment
        let end: Date
        let title: String
    }

    private let aggregationService = TimeAggregationService()
    private let dailySummaryService = DailySummaryService()
    private var ledgerBucketCache = LedgerBucketCache()
    private(set) var snapshots: [AnalyticsRange: AnalyticsSnapshot] = [:]

    func cachedSnapshot(for range: AnalyticsRange) -> AnalyticsSnapshot? {
        snapshots[range]
    }

    @discardableResult
    mutating func refreshSnapshot(
        range: AnalyticsRange,
        tasks: [TaskNode],
        segments: [TimeSegment],
        sessions: [TimeSession],
        taskPathByID: [UUID: String],
        taskParentPathByID: [UUID: String],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AnalyticsSnapshot {
        let rangeSegments = segmentsForAnalytics(segments, range: range, now: now, calendar: calendar)
        let snapshot = cachedDailySnapshot(
            range: range,
            tasks: tasks,
            rangeSegments: rangeSegments,
            sessions: sessions,
            taskPathByID: taskPathByID,
            taskParentPathByID: taskParentPathByID,
            now: now,
            calendar: calendar
        )
        snapshots[range] = snapshot
        return snapshot
    }

    mutating func refreshCachedSnapshots(
        tasks: [TaskNode],
        segments: [TimeSegment],
        sessions: [TimeSession],
        taskPathByID: [UUID: String],
        taskParentPathByID: [UUID: String],
        now: Date = Date(),
        calendar: Calendar = .current,
        invalidatedIntervals: [DateInterval] = []
    ) {
        guard !snapshots.isEmpty else { return }
        ledgerBucketCache.invalidate(intervals: invalidatedIntervals)
        for range in Array(snapshots.keys) {
            refreshSnapshot(
                range: range,
                tasks: tasks,
                segments: segments,
                sessions: sessions,
                taskPathByID: taskPathByID,
                taskParentPathByID: taskParentPathByID,
                now: now,
                calendar: calendar
            )
        }
    }

    func snapshot(
        range: AnalyticsRange,
        tasks: [TaskNode],
        segments: [TimeSegment],
        sessions: [TimeSession],
        taskPathByID: [UUID: String],
        taskParentPathByID: [UUID: String],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AnalyticsSnapshot {
        let rangeSegments = segmentsForAnalytics(segments, range: range, now: now, calendar: calendar)
        let daily = dailyBreakdown(
            segments: rangeSegments,
            range: range,
            now: now,
            calendar: calendar
        )
        return AnalyticsSnapshot(
            range: range,
            overview: overview(segments: rangeSegments, now: now),
            daily: daily,
            taskBreakdown: taskBreakdown(
                segments: rangeSegments,
                tasks: tasks,
                sessions: sessions,
                taskPathByID: taskPathByID,
                taskParentPathByID: taskParentPathByID,
                now: now
            ),
            overlaps: overlapSegments(
                segments: rangeSegments,
                tasks: tasks,
                sessions: sessions,
                now: now
            ),
            rangeSegments: rangeSegments
        )
    }

    mutating func invalidateLedgerBuckets(intervals: [DateInterval]) {
        ledgerBucketCache.invalidate(intervals: intervals)
    }

    mutating func clearLedgerBuckets() {
        ledgerBucketCache.removeAll()
    }

    var ledgerBucketCount: Int {
        ledgerBucketCache.bucketCount
    }

    private mutating func cachedDailySnapshot(
        range: AnalyticsRange,
        tasks: [TaskNode],
        rangeSegments: [TimeSegment],
        sessions: [TimeSession],
        taskPathByID: [UUID: String],
        taskParentPathByID: [UUID: String],
        now: Date,
        calendar: Calendar
    ) -> AnalyticsSnapshot {
        let daily = cachedDailyBreakdown(segments: rangeSegments, range: range, now: now, calendar: calendar)
        return AnalyticsSnapshot(
            range: range,
            overview: overview(segments: rangeSegments, now: now),
            daily: daily,
            taskBreakdown: taskBreakdown(
                segments: rangeSegments,
                tasks: tasks,
                sessions: sessions,
                taskPathByID: taskPathByID,
                taskParentPathByID: taskParentPathByID,
                now: now
            ),
            overlaps: overlapSegments(
                segments: rangeSegments,
                tasks: tasks,
                sessions: sessions,
                now: now
            ),
            rangeSegments: rangeSegments
        )
    }

    private func overview(segments: [TimeSegment], now: Date) -> AnalyticsOverview {
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

    private func dailyBreakdown(
        segments: [TimeSegment],
        range: AnalyticsRange,
        now: Date,
        calendar: Calendar
    ) -> [DailyAnalyticsPoint] {
        guard let interval = analyticsInterval(for: range, now: now, calendar: calendar) else { return [] }
        return dailySummaryService.summaries(segments: segments, interval: interval, now: now, calendar: calendar).map { summary in
            DailyAnalyticsPoint(
                date: summary.date,
                grossSeconds: summary.grossSeconds,
                wallSeconds: summary.wallClockSeconds,
                label: dayLabel(for: summary.date, range: range, calendar: calendar)
            )
        }
    }

    private mutating func cachedDailyBreakdown(
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

    private func segmentsForAnalytics(_ segments: [TimeSegment], range: AnalyticsRange, now: Date, calendar: Calendar) -> [TimeSegment] {
        guard let interval = analyticsInterval(for: range, now: now, calendar: calendar) else { return segments }
        return segments.filter { overlaps($0, interval: interval, now: now) }
    }

    private func taskBreakdown(
        segments: [TimeSegment],
        tasks: [TaskNode],
        sessions: [TimeSession],
        taskPathByID: [UUID: String],
        taskParentPathByID: [UUID: String],
        now: Date
    ) -> [TaskAnalyticsPoint] {
        let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let sessionsByTaskID = Dictionary(grouping: sessions, by: \.taskID)
        let grouped = Dictionary(grouping: segments, by: \.taskID)

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

    private func overlapSegments(
        segments: [TimeSegment],
        tasks: [TaskNode],
        sessions: [TimeSession],
        now: Date
    ) -> [OverlapAnalyticsPoint] {
        struct Event {
            let date: Date
            let isStart: Bool
            let segmentID: UUID
        }

        let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let sessionsByTaskID = Dictionary(grouping: sessions, by: \.taskID)
        let boundedSegments = segments.compactMap { segment -> BoundedOverlapSegment? in
            let end = segment.endedAt ?? now
            guard segment.deletedAt == nil, end > segment.startedAt else { return nil }
            return BoundedOverlapSegment(
                segment: segment,
                end: end,
                title: displayTitle(for: segment, taskByID: taskByID, sessionsByTaskID: sessionsByTaskID)
            )
        }
        let boundedByID = Dictionary(uniqueKeysWithValues: boundedSegments.map { ($0.segment.id, $0) })

        var events: [Event] = []
        for item in boundedSegments {
            events.append(Event(date: item.segment.startedAt, isStart: true, segmentID: item.segment.id))
            events.append(Event(date: item.end, isStart: false, segmentID: item.segment.id))
        }

        events.sort { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.isStart == false && rhs.isStart == true
            }
            return lhs.date < rhs.date
        }

        var active: [UUID: BoundedOverlapSegment] = [:]
        var overlaps: [OverlapAnalyticsPoint] = []
        var cursor = events.first?.date
        var index = events.startIndex

        while index < events.endIndex {
            let date = events[index].date
            if let start = cursor, date > start, active.count > 1 {
                let pair = firstTwoActiveOverlaps(active.values)
                if let first = pair.first, let second = pair.second {
                    overlaps.append(
                        OverlapAnalyticsPoint(
                            start: start,
                            end: date,
                            firstTitle: first.title,
                            secondTitle: second.title
                        )
                    )
                }
            }

            while index < events.endIndex, events[index].date == date, events[index].isStart == false {
                active.removeValue(forKey: events[index].segmentID)
                index = events.index(after: index)
            }
            while index < events.endIndex, events[index].date == date, events[index].isStart == true {
                if let bounded = boundedByID[events[index].segmentID] {
                    active[events[index].segmentID] = bounded
                }
                index = events.index(after: index)
            }
            cursor = date
        }

        return overlaps.sorted { $0.durationSeconds > $1.durationSeconds }
    }

    private func firstTwoActiveOverlaps(
        _ active: Dictionary<UUID, BoundedOverlapSegment>.Values
    ) -> (first: BoundedOverlapSegment?, second: BoundedOverlapSegment?) {
        var first: BoundedOverlapSegment?
        var second: BoundedOverlapSegment?

        for candidate in active {
            if first.map({ overlapPrecedes(candidate, $0) }) ?? true {
                second = first
                first = candidate
            } else if second.map({ overlapPrecedes(candidate, $0) }) ?? true {
                second = candidate
            }
        }

        return (first, second)
    }

    private func overlapPrecedes(_ lhs: BoundedOverlapSegment, _ rhs: BoundedOverlapSegment) -> Bool {
        if lhs.segment.startedAt == rhs.segment.startedAt {
            if lhs.title == rhs.title {
                return lhs.segment.id.uuidString < rhs.segment.id.uuidString
            }
            return lhs.title < rhs.title
        }
        return lhs.segment.startedAt < rhs.segment.startedAt
    }

    private func displayTitle(
        for segment: TimeSegment,
        taskByID: [UUID: TaskNode],
        sessionsByTaskID: [UUID: [TimeSession]]
    ) -> String {
        taskByID[segment.taskID]?.title ?? sessionsByTaskID[segment.taskID]?.first?.titleSnapshot ?? AppStrings.localized("task.deleted")
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
