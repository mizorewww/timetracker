import Foundation
import SwiftData

@MainActor
struct PomodoroCommandHandler {
    func start(
        taskID: UUID,
        focusSeconds: Int,
        breakSeconds: Int,
        longBreakSeconds: Int?,
        targetRounds: Int,
        allowParallelTimers: Bool,
        activeSegments: [TimeSegment],
        pomodoroRuns: [PomodoroRun],
        timeRepository: TimeTrackingRepository,
        pomodoroRepository: PomodoroRepository,
        context: ModelContext?
    ) throws -> PomodoroRun {
        if allowParallelTimers == false {
            try TimerCommandHandler().stopOtherActiveSegments(
                excluding: taskID,
                activeSegments: activeSegments,
                pomodoroRuns: pomodoroRuns,
                timeRepository: timeRepository,
                context: context
            )
        }
        return try StartPomodoroUseCase(repository: pomodoroRepository).execute(
            taskID: taskID,
            focusSeconds: focusSeconds,
            breakSeconds: breakSeconds,
            longBreakSeconds: longBreakSeconds,
            targetRounds: targetRounds
        )
    }

    func complete(run: PomodoroRun, repository: PomodoroRepository) throws {
        try CompletePomodoroFocusUseCase(repository: repository).execute(runID: run.id)
    }

    func cancel(run: PomodoroRun, discardRecord: Bool = false, repository: PomodoroRepository) throws {
        try CancelPomodoroUseCase(repository: repository).execute(runID: run.id, discardRecord: discardRecord)
    }

    func cancelIfNeeded(sessionID: UUID, runs: [PomodoroRun], context: ModelContext?, now: Date = Date()) throws {
        guard let run = runs.first(where: { $0.sessionID == sessionID && $0.deletedAt == nil && $0.endedAt == nil }) else {
            return
        }
        let shouldDiscard = try shouldDiscardCancelledRun(run, sessionID: sessionID, context: context, now: now)
        if shouldDiscard {
            try discardRunAndSession(run, sessionID: sessionID, context: context, now: now)
            return
        }
        run.state = .cancelled
        run.endedAt = now
        run.updatedAt = now
        run.clientMutationID = UUID()
        try context?.save()
    }

    private func shouldDiscardCancelledRun(
        _ run: PomodoroRun,
        sessionID: UUID,
        context: ModelContext?,
        now: Date
    ) throws -> Bool {
        guard context != nil else { return false }
        let effectiveSeconds = try pomodoroEffectiveSeconds(sessionID: sessionID, context: context, now: now)
        return effectiveSeconds < Int(Double(max(1, run.focusSecondsPlanned)) * 0.2)
    }

    private func pomodoroEffectiveSeconds(sessionID: UUID, context: ModelContext?, now: Date) throws -> Int {
        guard let context else { return 0 }
        let segments = try segments(in: sessionID, context: context)
        return segments.reduce(0) { total, segment in
            guard segment.deletedAt == nil else { return total }
            return total + max(0, Int((segment.endedAt ?? now).timeIntervalSince(segment.startedAt)))
        }
    }

    private func discardRunAndSession(
        _ run: PomodoroRun,
        sessionID: UUID,
        context: ModelContext?,
        now: Date
    ) throws {
        run.state = .cancelled
        run.endedAt = now
        run.deletedAt = now
        run.updatedAt = now
        run.clientMutationID = UUID()

        guard let context else { return }
        for segment in try segments(in: sessionID, context: context) {
            segment.endedAt = segment.endedAt ?? now
            segment.deletedAt = now
            segment.updatedAt = now
        }
        if let session = try session(id: sessionID, context: context) {
            session.endedAt = session.endedAt ?? now
            session.deletedAt = now
            session.updatedAt = now
        }
        try context.save()
    }

    private func segments(in sessionID: UUID, context: ModelContext) throws -> [TimeSegment] {
        let targetSessionID = sessionID
        let descriptor = FetchDescriptor<TimeSegment>(
            predicate: #Predicate { $0.sessionID == targetSessionID },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return try context.fetch(descriptor)
    }

    private func session(id: UUID, context: ModelContext) throws -> TimeSession? {
        let sessionID = id
        var descriptor = FetchDescriptor<TimeSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
