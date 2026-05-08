import Foundation

extension TimeTrackerStore {
    func presentManualTime(taskID: UUID? = nil) {
        let target = taskID ?? selectedTaskID ?? tasks.first?.id
        manualTimeDraft = ManualTimeDraft(taskID: target, tasks: tasks)
    }

    func saveManualTimeDraft(_ draft: ManualTimeDraft) {
        guard let taskID = draft.taskID else {
            fail(.taskSelectionRequired)
            return
        }
        guard draft.endedAt > draft.startedAt else {
            fail(.invalidTimeRange)
            return
        }

        perform(event: .ledgerChanged(taskID: taskID, dateInterval: StoreInvalidationRange(start: draft.startedAt, end: draft.endedAt), isVisible: false)) {
            try ledgerCommandHandler.addManualTime(draft: draft, taskID: taskID, repository: requiredTimeRepository())
        }
        manualTimeDraft = nil
    }

    func presentEditSegment(_ segment: TimeSegment) {
        segmentEditorDraft = SegmentEditorDraft(segment: segment, note: note(for: segment))
    }

    func saveSegmentDraft(_ draft: SegmentEditorDraft) {
        guard let taskID = draft.taskID else {
            fail(.taskSelectionRequired)
            return
        }

        let endedAt = draft.isActive ? nil : draft.endedAt
        if let endedAt, endedAt <= draft.startedAt {
            fail(.invalidTimeRange)
            return
        }

        let newRange = StoreInvalidationRange(start: draft.startedAt, end: draft.endedAt)
        var events: Set<StoreDomainEvent> = [
            .ledgerChanged(taskID: taskID, dateInterval: newRange, isVisible: false)
        ]
        if let existingSegment = allSegments.first(where: { $0.id == draft.segmentID }) {
            let oldRange = StoreInvalidationRange(
                start: existingSegment.startedAt,
                end: existingSegment.endedAt ?? draft.endedAt
            )
            events.insert(.ledgerChanged(taskID: existingSegment.taskID, dateInterval: oldRange, isVisible: false))
        }

        perform(events: events) {
            try ledgerCommandHandler.updateSegment(draft: draft, taskID: taskID, repository: requiredTimeRepository())
            selectedTaskID = taskID
        }
        segmentEditorDraft = nil
    }

    func deleteSegment(_ segmentID: UUID) {
        let existingSegment = allSegments.first { $0.id == segmentID }
        let range = existingSegment.map {
            StoreInvalidationRange(start: $0.startedAt, end: $0.endedAt ?? Date())
        }
        perform(event: .ledgerChanged(taskID: existingSegment?.taskID ?? segmentEditorDraft?.taskID, dateInterval: range, isVisible: existingSegment?.isActive == true)) {
            try ledgerCommandHandler.softDeleteSegment(segmentID, repository: requiredTimeRepository())
        }
        segmentEditorDraft = nil
    }
}
