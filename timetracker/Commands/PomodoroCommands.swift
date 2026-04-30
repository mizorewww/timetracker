import Foundation
import SwiftData

@MainActor
struct PomodoroCommandHandler {
    func start(
        taskID: UUID,
        focusSeconds: Int,
        breakSeconds: Int,
        targetRounds: Int,
        allowParallelTimers: Bool,
        activeSegments: [TimeSegment],
        pomodoroRuns: [PomodoroRun],
        timeRepository: TimeTrackingRepository,
        pomodoroRepository: PomodoroRepository,
        context: ModelContext?
    ) throws -> PomodoroRun {
        if allowParallelTimers == false {
            try TimerCommandHandler().pauseOtherActiveSegments(
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
            targetRounds: targetRounds
        )
    }

    func complete(run: PomodoroRun, repository: PomodoroRepository) throws {
        try CompletePomodoroFocusUseCase(repository: repository).execute(runID: run.id)
    }

    func cancel(run: PomodoroRun, repository: PomodoroRepository) throws {
        try CancelPomodoroUseCase(repository: repository).execute(runID: run.id)
    }

    func interruptIfNeeded(sessionID: UUID, runs: [PomodoroRun], context: ModelContext?, now: Date = Date()) throws {
        guard let run = runs.first(where: { $0.sessionID == sessionID && $0.deletedAt == nil && $0.endedAt == nil }),
              run.state == .focusing else {
            return
        }
        run.state = .interrupted
        run.updatedAt = now
        run.clientMutationID = UUID()
        try context?.save()
    }

    func resumeIfNeeded(sessionID: UUID, runs: [PomodoroRun], context: ModelContext?, now: Date = Date()) throws {
        guard let run = runs.first(where: { $0.sessionID == sessionID && $0.deletedAt == nil && $0.endedAt == nil }),
              run.state == .interrupted else {
            return
        }
        run.state = .focusing
        run.updatedAt = now
        run.clientMutationID = UUID()
        try context?.save()
    }

    func cancelIfNeeded(sessionID: UUID, runs: [PomodoroRun], context: ModelContext?, now: Date = Date()) throws {
        guard let run = runs.first(where: { $0.sessionID == sessionID && $0.deletedAt == nil && $0.endedAt == nil }) else {
            return
        }
        run.state = .cancelled
        run.endedAt = now
        run.updatedAt = now
        run.clientMutationID = UUID()
        try context?.save()
    }
}
