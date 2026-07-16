import Foundation

extension TimeTrackerStore {
    @discardableResult
    func saveManualTimeDraft(_ draft: ManualTimeDraft) -> Bool {
        guard let taskID = draft.taskID else {
            fail(.taskSelectionRequired)
            return false
        }
        guard draft.endedAt > draft.startedAt else {
            fail(.invalidTimeRange)
            return false
        }
        guard trackableTaskIDs.contains(taskID) else {
            fail(.taskTrackingUnavailable)
            return false
        }

        let didSave = perform(event: .ledgerChanged(taskID: taskID, dateInterval: StoreInvalidationRange(start: draft.startedAt, end: draft.endedAt), isVisible: false)) {
            try ledgerCommandHandler.addManualTime(draft: draft, taskID: taskID, repository: requiredTimeRepository())
        }
        return didSave
    }

    @discardableResult
    func saveSegmentDraft(_ draft: SegmentEditorDraft) -> Bool {
        guard let taskID = draft.taskID else {
            fail(.taskSelectionRequired)
            return false
        }
        let existingSegment = ledgerDomainStore.segment(for: draft.segmentID)
        guard existingSegment?.endedAt == nil || draft.isActive == false else {
            fail(.closedSegmentCannotReopen)
            return false
        }
        let isRetainingUnavailableHistoricalAssignment =
            existingSegment?.taskID == taskID && draft.isActive == false
        guard trackableTaskIDs.contains(taskID) || isRetainingUnavailableHistoricalAssignment else {
            fail(.taskTrackingUnavailable)
            return false
        }

        let now = Date()
        if draft.isActive, draft.startedAt > now {
            fail(.activeTimerStartInFuture)
            return false
        }

        let endedAt = draft.isActive ? nil : draft.endedAt
        if let endedAt, endedAt <= draft.startedAt {
            fail(.invalidTimeRange)
            return false
        }

        let effectiveEnd = max(
            draft.startedAt,
            TrackedTimePolicy.boundedEnd(endedAt: endedAt, now: now)
        )
        let newRange = StoreInvalidationRange(start: draft.startedAt, end: effectiveEnd)
        var events: Set<StoreDomainEvent> = [
            .ledgerChanged(taskID: taskID, dateInterval: newRange, isVisible: false)
        ]
        let activePomodoroSessionID = activePomodoroSessionID(for: existingSegment)
        if let existingSegment {
            let oldRange = StoreInvalidationRange(
                start: existingSegment.startedAt,
                end: max(
                    existingSegment.startedAt,
                    TrackedTimePolicy.boundedEnd(endedAt: existingSegment.endedAt, now: now)
                )
            )
            events.insert(.ledgerChanged(taskID: existingSegment.taskID, dateInterval: oldRange, isVisible: false))
        }
        if let activePomodoroSessionID,
           let run = pomodoroRuns.first(where: { $0.sessionID == activePomodoroSessionID }) {
            events.insert(.pomodoroChanged(runID: run.id, sessionID: activePomodoroSessionID, taskID: taskID))
        }

        let didSave = perform(events: events) {
            try ledgerCommandHandler.updateSegment(
                draft: draft,
                taskID: taskID,
                activePomodoroSessionID: activePomodoroSessionID,
                pomodoroRuns: pomodoroRuns,
                repository: requiredTimeRepository(),
                context: modelContext
            )
        }
        if didSave {
            selectedTaskID = taskID
        }
        return didSave
    }

    @discardableResult
    func deleteSegment(_ segmentID: UUID, fallbackTaskID: UUID? = nil) -> Bool {
        let existingSegment = ledgerDomainStore.segment(for: segmentID)
        let activePomodoroSessionID = activePomodoroSessionID(for: existingSegment)
        let now = Date()
        let range = existingSegment.map {
            StoreInvalidationRange(
                start: $0.startedAt,
                end: max(
                    $0.startedAt,
                    TrackedTimePolicy.boundedEnd(endedAt: $0.endedAt, now: now)
                )
            )
        }
        var events: Set<StoreDomainEvent> = [
            .ledgerChanged(
                taskID: existingSegment?.taskID ?? fallbackTaskID,
                dateInterval: range,
                isVisible: existingSegment?.isActive == true
            )
        ]
        if let activePomodoroSessionID,
           let run = pomodoroRuns.first(where: { $0.sessionID == activePomodoroSessionID }) {
            events.insert(
                .pomodoroChanged(
                    runID: run.id,
                    sessionID: activePomodoroSessionID,
                    taskID: run.taskID
                )
            )
        }
        let didDelete = perform(events: events) {
            try ledgerCommandHandler.softDeleteSegment(
                segmentID,
                activePomodoroSessionID: activePomodoroSessionID,
                pomodoroRuns: pomodoroRuns,
                repository: requiredTimeRepository(),
                context: modelContext
            )
        }
        return didDelete
    }

    private func activePomodoroSessionID(for segment: TimeSegment?) -> UUID? {
        guard let segment,
              segment.source == .pomodoro,
              segment.isActive,
              pomodoroRuns.contains(where: {
                  $0.sessionID == segment.sessionID &&
                      $0.deletedAt == nil &&
                      $0.endedAt == nil
              }) else {
            return nil
        }
        return segment.sessionID
    }
}
