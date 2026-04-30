import Foundation

@MainActor
struct LedgerCommandHandler {
    @discardableResult
    func addManualTime(draft: ManualTimeDraft, taskID: UUID, repository: TimeTrackingRepository) throws -> TimeSegment {
        try AddManualTimeUseCase(repository: repository).execute(
            taskID: taskID,
            startedAt: draft.startedAt,
            endedAt: draft.endedAt,
            note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Manual"
        )
    }

    func updateSegment(draft: SegmentEditorDraft, taskID: UUID, repository: TimeTrackingRepository) throws {
        let endedAt = draft.isActive ? nil : draft.endedAt
        try UpdateSegmentUseCase(repository: repository).execute(
            segmentID: draft.segmentID,
            taskID: taskID,
            startedAt: draft.startedAt,
            endedAt: endedAt,
            note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }

    func softDeleteSegment(_ segmentID: UUID, repository: TimeTrackingRepository) throws {
        try SoftDeleteSegmentUseCase(repository: repository).execute(segmentID: segmentID)
    }
}
