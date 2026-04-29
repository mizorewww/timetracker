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
    private let engine = AnalyticsEngine()
    private let aggregationService = TimeAggregationService()
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
        let snapshot = snapshot(
            range: range,
            tasks: tasks,
            segments: segments,
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
        calendar: Calendar = .current
    ) {
        guard !snapshots.isEmpty else { return }
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
        return AnalyticsSnapshot(
            range: range,
            overview: engine.overview(segments: segments, range: range, now: now, calendar: calendar),
            daily: engine.dailyBreakdown(segments: segments, range: range, now: now, calendar: calendar),
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
            let segment: TimeSegment
        }

        let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let sessionsByTaskID = Dictionary(grouping: sessions, by: \.taskID)
        let boundedSegments = segments.compactMap { segment -> (segment: TimeSegment, end: Date)? in
            let end = segment.endedAt ?? now
            guard segment.deletedAt == nil, end > segment.startedAt else { return nil }
            return (segment, end)
        }

        var events: [Event] = []
        for item in boundedSegments {
            events.append(Event(date: item.segment.startedAt, isStart: true, segment: item.segment))
            events.append(Event(date: item.end, isStart: false, segment: item.segment))
        }

        events.sort { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.isStart == false && rhs.isStart == true
            }
            return lhs.date < rhs.date
        }

        var active: [UUID: TimeSegment] = [:]
        var overlaps: [OverlapAnalyticsPoint] = []
        var cursor = events.first?.date
        var index = events.startIndex

        while index < events.endIndex {
            let date = events[index].date
            if let start = cursor, date > start, active.count > 1 {
                let activeSegments = active.values.sorted {
                    if $0.startedAt == $1.startedAt {
                        return displayTitle(for: $0, taskByID: taskByID, sessionsByTaskID: sessionsByTaskID) <
                            displayTitle(for: $1, taskByID: taskByID, sessionsByTaskID: sessionsByTaskID)
                    }
                    return $0.startedAt < $1.startedAt
                }
                if let first = activeSegments.first, let second = activeSegments.dropFirst().first {
                    overlaps.append(
                        OverlapAnalyticsPoint(
                            start: start,
                            end: date,
                            firstTitle: displayTitle(for: first, taskByID: taskByID, sessionsByTaskID: sessionsByTaskID),
                            secondTitle: displayTitle(for: second, taskByID: taskByID, sessionsByTaskID: sessionsByTaskID)
                        )
                    )
                }
            }

            while index < events.endIndex, events[index].date == date, events[index].isStart == false {
                active.removeValue(forKey: events[index].segment.id)
                index = events.index(after: index)
            }
            while index < events.endIndex, events[index].date == date, events[index].isStart == true {
                active[events[index].segment.id] = events[index].segment
                index = events.index(after: index)
            }
            cursor = date
        }

        return overlaps.sorted { $0.durationSeconds > $1.durationSeconds }
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

    private func overlaps(_ segment: TimeSegment, interval: DateInterval, now: Date) -> Bool {
        let end = segment.endedAt ?? now
        return segment.deletedAt == nil && segment.startedAt < interval.end && end > interval.start
    }
}
