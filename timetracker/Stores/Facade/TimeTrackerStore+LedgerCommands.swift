import Foundation

extension TimeTrackerStore {
    func presentManualTime(taskID: UUID? = nil) {
        let target = taskID ?? selectedTaskID ?? tasks.first?.id
        manualTimeDraft = ManualTimeDraft(taskID: target, tasks: tasks)
    }

    func saveManualTimeDraft(_ draft: ManualTimeDraft) {
        guard let taskID = draft.taskID else {
            errorMessage = AppStrings.localized("task.selectRequired")
            return
        }
        guard draft.endedAt > draft.startedAt else {
            errorMessage = AppStrings.localized("time.endAfterStart")
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
            errorMessage = AppStrings.localized("task.selectRequired")
            return
        }

        let endedAt = draft.isActive ? nil : draft.endedAt
        if let endedAt, endedAt <= draft.startedAt {
            errorMessage = AppStrings.localized("time.endAfterStart")
            return
        }

        perform(event: .ledgerChanged(taskID: taskID, dateInterval: StoreInvalidationRange(start: draft.startedAt, end: draft.endedAt), isVisible: false)) {
            try ledgerCommandHandler.updateSegment(draft: draft, taskID: taskID, repository: requiredTimeRepository())
            selectedTaskID = taskID
        }
        segmentEditorDraft = nil
    }

    func deleteSegment(_ segmentID: UUID) {
        perform(event: .ledgerChanged(taskID: segmentEditorDraft?.taskID, dateInterval: nil, isVisible: false)) {
            try ledgerCommandHandler.softDeleteSegment(segmentID, repository: requiredTimeRepository())
        }
        segmentEditorDraft = nil
    }
}
