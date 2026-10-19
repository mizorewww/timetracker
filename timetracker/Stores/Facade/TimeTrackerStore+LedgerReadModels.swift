import Foundation

extension TimeTrackerStore {
    var timelineSegments: [TimeSegment] {
        sortedTodaySegments
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

    func segmentEditorDraft(for segment: TimeSegment) -> SegmentEditorDraft? {
        guard let session = ledgerDomainStore.session(for: segment.sessionID) ??
            sessions.first(where: { $0.id == segment.sessionID })
        else {
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
              })
        else {
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

    func segmentEditorDraft(for entryID: TimelineEntryID) -> SegmentEditorDraft? {
        guard case let .trackedSegment(segmentID) = entryID,
              let segment = ledgerDomainStore.segment(for: segmentID),
              segment.deletedAt == nil,
              isReadableLedgerSegment(segment)
        else {
            return nil
        }
        return segmentEditorDraft(for: segment)
    }

    func secondsForTaskTotalRollup(_ task: TaskNode, mode: AggregationMode = .gross, now: Date = Date()) -> Int {
        let ids = taskAndDescendantIDs(for: task.id)
        return LedgerSummaryService.totalSeconds(taskIDs: ids, segments: allSegments, mode: mode, now: now)
    }

    func visibleSegments(overlapping interval: DateInterval, now: Date) -> [TimeSegment] {
        visibleSegments(
            overlapping: interval,
            evaluatedAt: now,
            clockReference: now
        )
    }

    /// `clockReference` is kept for API compatibility; range reads scan the
    /// ledger snapshots, so only `cutoff` affects the result.
    func visibleSegments(
        overlapping interval: DateInterval,
        evaluatedAt cutoff: Date,
        clockReference _: Date
    ) -> [TimeSegment] {
        ledgerDomainStore.segments(overlapping: interval, now: cutoff)
            .filter(isReadableLedgerSegment)
    }

    func visibleSessions(for segments: [TimeSegment]) -> [TimeSession] {
        ledgerDomainStore.sessions(for: Set(segments.map(\.sessionID)))
    }
}
