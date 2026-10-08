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
        guard case let .trackedSegment(segmentID) = entryID else {
            return nil
        }

        let segment: TimeSegment? = if ledgerDomainStore.hasIndexedSegmentHistory {
            ledgerDomainStore.segment(for: segmentID).flatMap { candidate in
                guard candidate.deletedAt == nil,
                      isReadableLedgerSegment(candidate)
                else {
                    return nil
                }
                return candidate
            }
        } else {
            allSegments
                .visibleDeduplicatedByID()
                .first { $0.id == segmentID }
        }

        guard let segment else {
            return nil
        }
        return segmentEditorDraft(for: segment)
    }

    func secondsForTaskTotalRollup(_ task: TaskNode, mode: AggregationMode = .gross, now: Date = Date()) -> Int {
        let ids = taskAndDescendantIDs(for: task.id)
        return ledgerSummaryService.totalSeconds(taskIDs: ids, segments: allSegments, mode: mode, now: now)
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
