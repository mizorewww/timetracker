import Foundation

extension TimeTrackerStore {
    var timelineSegments: [TimeSegment] {
        sortedTodaySegments
    }

    func timelineSegments(for date: Date, now: Date = Date()) -> [TimeSegment] {
        guard let interval = Calendar.current.dateInterval(of: .day, for: date) else {
            return []
        }
        return allSegments
            .filter { segment in
                guard segment.deletedAt == nil else { return false }
                let end = segment.endedAt ?? now
                return segment.startedAt < interval.end && end > interval.start
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var todayGrossSeconds: Int {
        todayGrossSeconds(now: Date())
    }

    var todayWallSeconds: Int {
        todayWallSeconds(now: Date())
    }

    func todayGrossSeconds(now: Date) -> Int {
        aggregationService.totalSeconds(segments: todaySegments, mode: .gross, now: now)
    }

    func todayWallSeconds(now: Date) -> Int {
        aggregationService.totalSeconds(segments: todaySegments, mode: .wallClock, now: now)
    }

    func dayGrossSeconds(for date: Date, now: Date = Date()) -> Int {
        daySeconds(for: date, mode: .gross, now: now)
    }

    func dayWallSeconds(for date: Date, now: Date = Date()) -> Int {
        daySeconds(for: date, mode: .wallClock, now: now)
    }

    func daySeconds(for date: Date, mode: AggregationMode = .gross, now: Date = Date()) -> Int {
        guard let interval = Calendar.current.dateInterval(of: .day, for: date) else { return 0 }
        return ledgerSummaryService.secondsInInterval(
            taskIDs: Set(allSegments.map(\.taskID)),
            segments: allSegments,
            interval: interval,
            mode: mode,
            now: now
        )
    }

    func overlapSeconds(now: Date) -> Int {
        max(0, todayGrossSeconds(now: now) - todayWallSeconds(now: now))
    }

    var overlapSeconds: Int {
        max(0, todayGrossSeconds - todayWallSeconds)
    }

    func activeSegment(for taskID: UUID) -> TimeSegment? {
        activeSegments.first { $0.taskID == taskID }
    }

    func displayTitle(for segment: TimeSegment) -> String {
        task(for: segment.taskID)?.title ?? AppStrings.localized("task.deleted")
    }

    func displayPath(for segment: TimeSegment) -> String {
        guard taskByID[segment.taskID] != nil else { return AppStrings.localized("task.deleted.path") }
        return taskParentPathByID[segment.taskID] ?? ""
    }

    func note(for segment: TimeSegment) -> String {
        sessions.first { $0.id == segment.sessionID }?.note ?? ""
    }

    func secondsForTaskTotal(_ task: TaskNode, mode: AggregationMode = .gross, now: Date = Date()) -> Int {
        ledgerSummaryService.totalSeconds(taskIDs: [task.id], segments: allSegments, mode: mode, now: now)
    }

    func secondsForTaskTotalRollup(_ task: TaskNode, mode: AggregationMode = .gross, now: Date = Date()) -> Int {
        let ids = taskAndDescendantIDs(for: task.id)
        return ledgerSummaryService.totalSeconds(taskIDs: ids, segments: allSegments, mode: mode, now: now)
    }

    func secondsForTaskToday(_ task: TaskNode, mode: AggregationMode = .gross) -> Int {
        let now = Date()
        guard let interval = Calendar.current.dateInterval(of: .day, for: now) else { return 0 }
        return ledgerSummaryService.secondsInInterval(taskIDs: [task.id], segments: allSegments, interval: interval, mode: mode, now: now)
    }

    func secondsForTaskTodayRollup(_ task: TaskNode, mode: AggregationMode = .gross, now: Date = Date()) -> Int {
        guard let interval = Calendar.current.dateInterval(of: .day, for: now) else { return 0 }
        let ids = taskAndDescendantIDs(for: task.id)
        return ledgerSummaryService.secondsInInterval(taskIDs: ids, segments: allSegments, interval: interval, mode: mode, now: now)
    }

    func secondsForTaskThisWeek(_ task: TaskNode, mode: AggregationMode = .gross, now: Date = Date()) -> Int {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return ledgerSummaryService.secondsInInterval(taskIDs: [task.id], segments: allSegments, interval: interval, mode: mode, now: now)
    }

    func secondsForTaskThisWeekRollup(_ task: TaskNode, mode: AggregationMode = .gross, now: Date = Date()) -> Int {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        let ids = taskAndDescendantIDs(for: task.id)
        return ledgerSummaryService.secondsInInterval(taskIDs: ids, segments: allSegments, interval: interval, mode: mode, now: now)
    }

    func recentSegments(for task: TaskNode, limit: Int = 6) -> [TimeSegment] {
        allSegments
            .filter { $0.taskID == task.id && $0.deletedAt == nil }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(limit)
            .map { $0 }
    }
}
