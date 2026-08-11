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
    func addManualTime(draft: ManualTimeDraft, taskID: UUID, repository: SwiftDataTimeTrackingRepository) throws -> TimeSegment {
        try repository.addManualSegment(
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
        repository: SwiftDataTimeTrackingRepository,
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
        repository: SwiftDataTimeTrackingRepository,
        context: ModelContext?
    ) throws {
        guard draft.wasActive || draft.isActive == false else {
            throw TimeTrackingRepositoryError.closedSegmentCannotReopen
        }
        let endedAt = draft.isActive ? nil : draft.endedAt
        try repository.updateSegment(
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
            fallbackStartedAt: draft.startedAt,
            runs: pomodoroRuns,
            context: context
        )
        if draft.wasActive, draft.isActive == false {
            try PomodoroCommandHandler(
                deviceID: deviceID,
                nowProvider: nowProvider
            ).cancelIfNeeded(
                sessionID: activePomodoroSessionID,
                runs: pomodoroRuns,
                context: context,
                now: draft.endedAt,
                discardShortAttempt: false
            )
        }
    }

    func softDeleteSegment(
        _ segmentID: UUID,
        activePomodoroSessionID: UUID? = nil,
        pomodoroRuns: [PomodoroRun] = [],
        repository: SwiftDataTimeTrackingRepository,
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
            try repository.softDeleteSegment(segmentID: segmentID)
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
        fallbackStartedAt: Date,
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
        let canonicalStartedAt: Date
        if let context {
            let targetSessionID = sessionID
            let descriptor = FetchDescriptor<TimeSession>(
                predicate: #Predicate { $0.id == targetSessionID }
            )
            canonicalStartedAt = try context.fetch(descriptor)
                .visibleDeduplicatedByID()
                .first?
                .startedAt ?? fallbackStartedAt
        } else {
            canonicalStartedAt = fallbackStartedAt
        }
        let mutationDate = nowProvider()
        run.taskID = taskID
        run.startedAt = canonicalStartedAt
        run.markMutated(at: mutationDate, deviceID: deviceID)
    }
}
