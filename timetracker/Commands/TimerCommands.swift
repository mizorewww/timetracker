import Foundation
import SwiftData

enum ExistingTaskTimerAdmission: Equatable {
    case reuseExisting
    case replaceExisting
}

struct TimerStartAdmission {
    let shouldStartNewSegment: Bool
    let segmentsToStop: [TimeSegment]
}

struct TimerStartAdmissionPolicy {
    func evaluate(
        taskID: UUID,
        allowParallelTimers: Bool,
        activeSegments: [TimeSegment],
        existingTaskAdmission: ExistingTaskTimerAdmission
    ) -> TimerStartAdmission {
        let liveSegments = activeSegments.filter {
            $0.endedAt == nil && $0.deletedAt == nil
        }
        let sameTaskSegments = liveSegments.filter { $0.taskID == taskID }
        let otherTaskSegments = liveSegments.filter { $0.taskID != taskID }
        let replacedSegments = existingTaskAdmission == .replaceExisting
            ? sameTaskSegments
            : []
        let exclusiveSegments = allowParallelTimers ? [] : otherTaskSegments

        return TimerStartAdmission(
            shouldStartNewSegment: sameTaskSegments.isEmpty || existingTaskAdmission == .replaceExisting,
            segmentsToStop: exclusiveSegments + replacedSegments
        )
    }
}

@MainActor
struct TimerCommandHandler {
    private let pomodoroCommandHandler: PomodoroCommandHandler

    init(
        deviceID: String? = nil,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        pomodoroCommandHandler = PomodoroCommandHandler(
            deviceID: deviceID,
            nowProvider: nowProvider
        )
    }

    func startTask(
        taskID: UUID,
        allowParallelTimers: Bool,
        activeSegments: [TimeSegment],
        pomodoroRuns: [PomodoroRun],
        timeRepository: TimeTrackingRepository,
        context: ModelContext?,
        source: TimeSessionSource = .timer
    ) throws {
        guard try prepareTaskStart(
            taskID: taskID,
            allowParallelTimers: allowParallelTimers,
            activeSegments: activeSegments,
            existingTaskAdmission: .reuseExisting,
            pomodoroRuns: pomodoroRuns,
            timeRepository: timeRepository,
            context: context
        ) else { return }
        _ = try StartTaskUseCase(repository: timeRepository).execute(taskID: taskID, source: source)
    }

    @discardableResult
    func prepareTaskStart(
        taskID: UUID,
        allowParallelTimers: Bool,
        activeSegments: [TimeSegment],
        existingTaskAdmission: ExistingTaskTimerAdmission,
        pomodoroRuns: [PomodoroRun],
        timeRepository: TimeTrackingRepository,
        context: ModelContext?
    ) throws -> Bool {
        let admission = TimerStartAdmissionPolicy().evaluate(
            taskID: taskID,
            allowParallelTimers: allowParallelTimers,
            activeSegments: activeSegments,
            existingTaskAdmission: existingTaskAdmission
        )
        for segment in admission.segmentsToStop {
            try stop(
                segment: segment,
                pomodoroRuns: pomodoroRuns,
                timeRepository: timeRepository,
                context: context
            )
        }
        return admission.shouldStartNewSegment
    }

    func stop(segment: TimeSegment, pomodoroRuns: [PomodoroRun], timeRepository: TimeTrackingRepository, context: ModelContext?) throws {
        let mutation = {
            // Reconcile/cancel the business run before issuing the generic
            // ledger stop. An expired Pomodoro clips its session to the
            // persisted phase deadline here; the idempotent segment stop then
            // has nothing left to extend to the current wall clock.
            try pomodoroCommandHandler.cancelIfNeeded(
                sessionID: segment.sessionID,
                runs: pomodoroRuns,
                context: context
            )
            try StopSegmentUseCase(repository: timeRepository).execute(segmentID: segment.id)
        }
        if let context {
            try context.performAtomicMutation(mutation)
        } else {
            try mutation()
        }
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
