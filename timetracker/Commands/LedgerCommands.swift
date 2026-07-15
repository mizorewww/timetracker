import Foundation
import SwiftData

@MainActor
struct LedgerCommandHandler {
    private let deviceID: String
    private let nowProvider: () -> Date

    init(
        deviceID: String? = nil,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.deviceID = deviceID ?? DeviceIdentity.current
        self.nowProvider = nowProvider
    }

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
        let mutation = {
            try updateSegmentMutation(
                draft: draft,
                taskID: taskID,
                activePomodoroSessionID: activePomodoroSessionID,
                pomodoroRuns: pomodoroRuns,
                repository: repository,
                context: context
            )
        }
        if let context {
            try context.performAtomicMutation(mutation)
        } else {
            try mutation()
        }
    }

    private func updateSegmentMutation(
        draft: SegmentEditorDraft,
        taskID: UUID,
        activePomodoroSessionID: UUID?,
        pomodoroRuns: [PomodoroRun],
        repository: TimeTrackingRepository,
        context: ModelContext?
    ) throws {
        guard draft.wasActive || draft.isActive == false else {
            throw TimeTrackingRepositoryError.closedSegmentCannotReopen
        }
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
            try PomodoroCommandHandler(
                deviceID: deviceID,
                nowProvider: nowProvider
            ).cancelIfNeeded(
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
        let mutation = {
            if let activePomodoroSessionID {
                try PomodoroCommandHandler(
                    deviceID: deviceID,
                    nowProvider: nowProvider
                ).discardIfNeeded(
                    sessionID: activePomodoroSessionID,
                    runs: pomodoroRuns,
                    context: context
                )
            }
            try SoftDeleteSegmentUseCase(repository: repository).execute(segmentID: segmentID)
        }
        if let context {
            try context.performAtomicMutation(mutation)
        } else {
            try mutation()
        }
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
        let mutationDate = nowProvider()
        run.taskID = taskID
        run.startedAt = startedAt
        run.markMutated(at: mutationDate, deviceID: deviceID)
    }
}
