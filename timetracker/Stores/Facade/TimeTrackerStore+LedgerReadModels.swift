import Foundation

extension TimeTrackerStore {
    var timelineSegments: [TimeSegment] {
        sortedTodaySegments
    }

    func timelineSegments(for date: Date, now: Date = Date()) -> [TimeSegment] {
        guard let interval = Calendar.current.dateInterval(of: .day, for: date) else {
            return []
        }
        return visibleSegments(overlapping: interval, now: now)
            .sorted { $0.startedAt > $1.startedAt }
    }

    var todayGrossSeconds: Int {
        todayGrossSeconds(now: Date())
    }

    var todayWallSeconds: Int {
        todayWallSeconds(now: Date())
    }

    func todayGrossSeconds(now: Date, calendar: Calendar = .current) -> Int {
        todaySeconds(now: now, mode: .gross, calendar: calendar)
    }

    func todayWallSeconds(now: Date, calendar: Calendar = .current) -> Int {
        todaySeconds(now: now, mode: .wallClock, calendar: calendar)
    }

    func dayGrossSeconds(for date: Date, now: Date = Date()) -> Int {
        daySeconds(for: date, mode: .gross, now: now)
    }

    func dayWallSeconds(for date: Date, now: Date = Date()) -> Int {
        daySeconds(for: date, mode: .wallClock, now: now)
    }

    func daySeconds(for date: Date, mode: AggregationMode = .gross, now: Date = Date()) -> Int {
        guard let interval = Calendar.current.dateInterval(of: .day, for: date) else { return 0 }
        let segments = visibleSegments(overlapping: interval, now: now)
        return ledgerSummaryService.secondsInInterval(
            taskIDs: Set(segments.map(\.taskID)),
            segments: segments,
            interval: interval,
            mode: mode,
            now: now
        )
    }

    private func todaySeconds(now: Date, mode: AggregationMode, calendar: Calendar) -> Int {
        guard let interval = calendar.dateInterval(of: .day, for: now) else { return 0 }
        let segments = visibleSegments(overlapping: interval, now: now)
        return ledgerSummaryService.secondsInInterval(
            taskIDs: Set(segments.map(\.taskID)),
            segments: segments,
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
        activeSegmentByTaskID[taskID]
    }

    func displayTitle(for segment: TimeSegment) -> String {
        task(for: segment.taskID)?.title ?? AppStrings.localized("task.unavailable")
    }

    func displayPath(for segment: TimeSegment) -> String {
        guard taskByID[segment.taskID] != nil else { return AppStrings.localized("task.unavailable.path") }
        return taskParentPathByID[segment.taskID] ?? ""
    }

    func note(for segment: TimeSegment) -> String {
        if ledgerDomainStore.hasIndexedSegmentHistory {
            return ledgerDomainStore.session(for: segment.sessionID)?.note ?? ""
        }
        return sessions.first { $0.id == segment.sessionID }?.note ?? ""
    }

    func segmentEditorDraft(for segment: TimeSegment) -> SegmentEditorDraft? {
        guard let session = ledgerDomainStore.session(for: segment.sessionID) ??
            sessions.first(where: { $0.id == segment.sessionID }) else {
            return nil
        }
        let linkedRuns = pomodoroRuns.filter { run in
            run.sessionID == segment.sessionID &&
                run.deletedAt == nil &&
                run.endedAt == nil
        }
        guard linkedRuns.count <= 1,
              linkedRuns.allSatisfy({
                  $0.state == .focusing || $0.state == .interrupted
              }) else {
            return nil
        }
        let run = linkedRuns.first
        return SegmentEditorDraft(
            segment: segment,
            note: session.note ?? "",
            sessionMutationID: session.clientMutationID,
            pomodoroPhase: run.map(PomodoroPhaseToken.init)
        )
    }

    func secondsForTaskTotal(_ task: TaskNode, mode: AggregationMode = .gross, now: Date = Date()) -> Int {
        ledgerSummaryService.totalSeconds(taskIDs: [task.id], segments: allSegments, mode: mode, now: now)
    }

    func secondsForTaskTotalRollup(_ task: TaskNode, mode: AggregationMode = .gross, now: Date = Date()) -> Int {
        let ids = taskAndDescendantIDs(for: task.id)
        return ledgerSummaryService.totalSeconds(taskIDs: ids, segments: allSegments, mode: mode, now: now)
    }

    func secondsForTaskToday(
        _ task: TaskNode,
        mode: AggregationMode = .gross,
        now: Date = Date()
    ) -> Int {
        guard let interval = Calendar.current.dateInterval(of: .day, for: now) else { return 0 }
        let segments = visibleSegments(overlapping: interval, now: now)
        return ledgerSummaryService.secondsInInterval(taskIDs: [task.id], segments: segments, interval: interval, mode: mode, now: now)
    }

    func secondsForTaskTodayRollup(_ task: TaskNode, mode: AggregationMode = .gross, now: Date = Date()) -> Int {
        guard let interval = Calendar.current.dateInterval(of: .day, for: now) else { return 0 }
        let ids = taskAndDescendantIDs(for: task.id)
        let segments = visibleSegments(overlapping: interval, now: now)
        return ledgerSummaryService.secondsInInterval(taskIDs: ids, segments: segments, interval: interval, mode: mode, now: now)
    }

    func secondsForTaskThisWeek(_ task: TaskNode, mode: AggregationMode = .gross, now: Date = Date()) -> Int {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        let segments = visibleSegments(overlapping: interval, now: now)
        return ledgerSummaryService.secondsInInterval(taskIDs: [task.id], segments: segments, interval: interval, mode: mode, now: now)
    }

    func secondsForTaskThisWeekRollup(_ task: TaskNode, mode: AggregationMode = .gross, now: Date = Date()) -> Int {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        let ids = taskAndDescendantIDs(for: task.id)
        let segments = visibleSegments(overlapping: interval, now: now)
        return ledgerSummaryService.secondsInInterval(taskIDs: ids, segments: segments, interval: interval, mode: mode, now: now)
    }

    func recentSegments(for task: TaskNode, limit: Int = 6) -> [TimeSegment] {
        allSegments
            .filter { $0.taskID == task.id && $0.deletedAt == nil }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(limit)
            .map { $0 }
    }

    func visibleSegments(overlapping interval: DateInterval, now: Date) -> [TimeSegment] {
        visibleSegments(
            overlapping: interval,
            evaluatedAt: now,
            clockReference: now
        )
    }

    func visibleSegments(
        overlapping interval: DateInterval,
        evaluatedAt cutoff: Date,
        clockReference: Date
    ) -> [TimeSegment] {
        if ledgerDomainStore.hasIndexedSegmentHistory {
            return ledgerDomainStore.segments(
                overlapping: interval,
                evaluatedAt: cutoff,
                clockReference: clockReference
            )
                .filter(isReadableLedgerSegment)
        }
        return allSegments.filter { segment in
            guard segment.deletedAt == nil else { return false }
            return TrackedTimePolicy.overlaps(
                startedAt: segment.startedAt,
                endedAt: segment.endedAt,
                interval: interval,
                now: cutoff
            )
        }
    }

    func visibleSessions(for segments: [TimeSegment]) -> [TimeSession] {
        let sessionIDs = Set(segments.map(\.sessionID))
        if ledgerDomainStore.hasIndexedSegmentHistory {
            return ledgerDomainStore.sessions(for: sessionIDs)
        }
        return sessions.filter { sessionIDs.contains($0.id) && $0.deletedAt == nil }
    }
}
