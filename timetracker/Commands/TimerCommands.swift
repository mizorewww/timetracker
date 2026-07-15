import Foundation
import SwiftData

@MainActor
struct TimerCommandHandler {
    private let pomodoroCommandHandler = PomodoroCommandHandler()

    func startTask(
        taskID: UUID,
        allowParallelTimers: Bool,
        activeSegments: [TimeSegment],
        pomodoroRuns: [PomodoroRun],
        timeRepository: TimeTrackingRepository,
        context: ModelContext?,
        source: TimeSessionSource = .timer
    ) throws {
        if allowParallelTimers == false {
            try stopOtherActiveSegments(
                excluding: taskID,
                activeSegments: activeSegments,
                pomodoroRuns: pomodoroRuns,
                timeRepository: timeRepository,
                context: context
            )
        }
        if activeSegments.contains(where: { $0.taskID == taskID && $0.endedAt == nil && $0.deletedAt == nil }) {
            return
        }
        _ = try StartTaskUseCase(repository: timeRepository).execute(taskID: taskID, source: source)
    }

    func stop(segment: TimeSegment, pomodoroRuns: [PomodoroRun], timeRepository: TimeTrackingRepository, context: ModelContext?) throws {
        // Reconcile/cancel the business run before issuing the generic ledger
        // stop. An expired Pomodoro clips its session to the persisted phase
        // deadline here; the idempotent segment stop then has nothing left to
        // extend to the current wall clock.
        try pomodoroCommandHandler.cancelIfNeeded(sessionID: segment.sessionID, runs: pomodoroRuns, context: context)
        try StopSegmentUseCase(repository: timeRepository).execute(segmentID: segment.id)
    }

    func stopOtherActiveSegments(
        excluding taskID: UUID,
        activeSegments: [TimeSegment],
        pomodoroRuns: [PomodoroRun],
        timeRepository: TimeTrackingRepository,
        context: ModelContext?
    ) throws {
        for segment in activeSegments where segment.taskID != taskID {
            try stop(segment: segment, pomodoroRuns: pomodoroRuns, timeRepository: timeRepository, context: context)
        }
    }
}
