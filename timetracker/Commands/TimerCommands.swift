import Foundation
import SwiftData

@MainActor
struct TimerCommandHandler {
    private let pomodoroCommandHandler = PomodoroCommandHandler()

    func startTask(
        taskID: UUID,
        allowParallelTimers: Bool,
        activeSegments: [TimeSegment],
        pausedSessions: [TimeSession],
        pomodoroRuns: [PomodoroRun],
        timeRepository: TimeTrackingRepository,
        context: ModelContext?
    ) throws {
        if activeSegments.contains(where: { $0.taskID == taskID && $0.endedAt == nil && $0.deletedAt == nil }) {
            return
        }
        if allowParallelTimers == false {
            try pauseOtherActiveSegments(
                excluding: taskID,
                activeSegments: activeSegments,
                pomodoroRuns: pomodoroRuns,
                timeRepository: timeRepository,
                context: context
            )
        }
        if let pausedSession = pausedSessions.first(where: { $0.taskID == taskID && $0.endedAt == nil && $0.deletedAt == nil }) {
            _ = try ResumeSessionUseCase(repository: timeRepository).execute(sessionID: pausedSession.id)
            try pomodoroCommandHandler.resumeIfNeeded(sessionID: pausedSession.id, runs: pomodoroRuns, context: context)
            return
        }
        _ = try StartTaskUseCase(repository: timeRepository).execute(taskID: taskID, source: .timer)
    }

    func stop(segment: TimeSegment, pomodoroRuns: [PomodoroRun], timeRepository: TimeTrackingRepository, context: ModelContext?) throws {
        try StopSegmentUseCase(repository: timeRepository).execute(segmentID: segment.id)
        try pomodoroCommandHandler.cancelIfNeeded(sessionID: segment.sessionID, runs: pomodoroRuns, context: context)
    }

    func pause(segment: TimeSegment, pomodoroRuns: [PomodoroRun], timeRepository: TimeTrackingRepository, context: ModelContext?) throws {
        try PauseSessionUseCase(repository: timeRepository).execute(sessionID: segment.sessionID)
        try pomodoroCommandHandler.interruptIfNeeded(sessionID: segment.sessionID, runs: pomodoroRuns, context: context)
    }

    func resume(session: TimeSession, pomodoroRuns: [PomodoroRun], timeRepository: TimeTrackingRepository, context: ModelContext?) throws {
        _ = try ResumeSessionUseCase(repository: timeRepository).execute(sessionID: session.id)
        try pomodoroCommandHandler.resumeIfNeeded(sessionID: session.id, runs: pomodoroRuns, context: context)
    }

    func stop(session: TimeSession, pomodoroRuns: [PomodoroRun], timeRepository: TimeTrackingRepository, context: ModelContext?) throws {
        try StopSessionUseCase(repository: timeRepository).execute(sessionID: session.id)
        try pomodoroCommandHandler.cancelIfNeeded(sessionID: session.id, runs: pomodoroRuns, context: context)
    }

    func pauseOtherActiveSegments(
        excluding taskID: UUID,
        activeSegments: [TimeSegment],
        pomodoroRuns: [PomodoroRun],
        timeRepository: TimeTrackingRepository,
        context: ModelContext?
    ) throws {
        for segment in activeSegments where segment.taskID != taskID {
            try PauseSessionUseCase(repository: timeRepository).execute(sessionID: segment.sessionID)
            try pomodoroCommandHandler.interruptIfNeeded(sessionID: segment.sessionID, runs: pomodoroRuns, context: context)
        }
    }
}
