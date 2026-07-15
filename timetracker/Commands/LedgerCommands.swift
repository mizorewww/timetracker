import Foundation
import SwiftData

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

    func updateSegment(
        draft: SegmentEditorDraft,
        taskID: UUID,
        activePomodoroSessionID: UUID? = nil,
        pomodoroRuns: [PomodoroRun] = [],
        repository: TimeTrackingRepository,
        context: ModelContext? = nil
    ) throws {
        let endedAt = draft.isActive ? nil : draft.endedAt
        try UpdateSegmentUseCase(repository: repository).execute(
            segmentID: draft.segmentID,
            taskID: taskID,
            startedAt: draft.startedAt,
            endedAt: endedAt,
            note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        guard let activePomodoroSessionID else { return }
        try rebindActivePomodoro(
            sessionID: activePomodoroSessionID,
            taskID: taskID,
            startedAt: draft.startedAt,
            runs: pomodoroRuns,
            context: context
        )
        if draft.isActive {
            return
        } else {
            try PomodoroCommandHandler().cancelIfNeeded(
                sessionID: activePomodoroSessionID,
                runs: pomodoroRuns,
                context: context,
                now: draft.endedAt
            )
        }
    }

    func softDeleteSegment(
        _ segmentID: UUID,
        activePomodoroSessionID: UUID? = nil,
        pomodoroRuns: [PomodoroRun] = [],
        repository: TimeTrackingRepository,
        context: ModelContext? = nil
    ) throws {
        if let activePomodoroSessionID {
            try PomodoroCommandHandler().discardIfNeeded(
                sessionID: activePomodoroSessionID,
                runs: pomodoroRuns,
                context: context
            )
        }
        try SoftDeleteSegmentUseCase(repository: repository).execute(segmentID: segmentID)
    }

    private func rebindActivePomodoro(
        sessionID: UUID,
        taskID: UUID,
        startedAt: Date,
        runs: [PomodoroRun],
        context: ModelContext?
    ) throws {
        guard let run = runs.first(where: {
            $0.sessionID == sessionID &&
                $0.deletedAt == nil &&
                $0.endedAt == nil &&
                ($0.state == .focusing || $0.state == .interrupted)
        }) else {
            return
        }
        run.taskID = taskID
        run.startedAt = startedAt
        run.updatedAt = Date()
        run.clientMutationID = UUID()
        try context?.saveAfterMutationStep()
    }
}
