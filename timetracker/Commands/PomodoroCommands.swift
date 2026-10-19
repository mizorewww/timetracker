import Foundation
import SwiftData

struct StoppedTimerMutationOutcome: Equatable, Hashable, Sendable {
    let segmentID: UUID
    let sessionID: UUID
    let taskID: UUID
}

struct PomodoroBreakResumeOutcome: Equatable, Sendable {
    let runID: UUID
    let taskID: UUID
    let resumedSessionID: UUID
    let resumedSegmentID: UUID
    let stoppedSegments: [StoppedTimerMutationOutcome]
}

enum PomodoroCommandInvariantError: Error {
    case resumedLedgerSegmentMissing
    case stoppedLedgerSegmentStillActive
}

@MainActor
struct PomodoroCommandHandler {
    private let deviceID: String
    private let nowProvider: () -> Date

    init(
        deviceID: String? = nil,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.deviceID = deviceID ?? DeviceIdentity.current
        self.nowProvider = nowProvider
    }

    func start(
        taskID: UUID,
        focusSeconds: Int,
        breakSeconds: Int,
        longBreakSeconds: Int?,
        targetRounds: Int,
        allowParallelTimers: Bool,
        activeSegments: [TimeSegment],
        pomodoroRuns: [PomodoroRun],
        timeRepository: SwiftDataTimeTrackingRepository,
        pomodoroRepository: SwiftDataPomodoroRepository,
        context: ModelContext
    ) throws -> PomodoroRun {
        let mutation = { () throws -> PomodoroRun in
            if allowParallelTimers == false {
                for segment in activeSegments where segment.taskID != taskID {
                    try stopTimerSegment(
                        segment,
                        pomodoroRuns: pomodoroRuns,
                        timeRepository: timeRepository,
                        context: context
                    )
                }
            }
            return try pomodoroRepository.startPomodoro(
                taskID: taskID,
                focusSeconds: focusSeconds,
                breakSeconds: breakSeconds,
                longBreakSeconds: longBreakSeconds,
                targetRounds: targetRounds
            )
        }
        return try context.performAtomicMutation(mutation)
    }

    @discardableResult
    func completeFocus(
        runID: UUID,
        expectedState: PomodoroState,
        repository: SwiftDataPomodoroRepository
    ) throws -> Bool {
        guard expectedState == .focusing || expectedState == .interrupted else {
            return false
        }
        return try repository.completeFocus(
            runID: runID,
            expectedState: expectedState,
            endedAt: nowProvider()
        )
    }

    @discardableResult
    func resumeFocusAfterBreak(
        runID: UUID,
        expectedState: PomodoroState,
        allowParallelTimers: Bool,
        timeRepository: SwiftDataTimeTrackingRepository,
        repository: SwiftDataPomodoroRepository,
        context: ModelContext
    ) throws -> PomodoroBreakResumeOutcome? {
        let mutation = { () throws -> PomodoroBreakResumeOutcome? in
            guard expectedState == .shortBreak || expectedState == .longBreak,
                  let run = try repository.run(id: runID),
                  run.state == expectedState,
                  run.deletedAt == nil,
                  run.endedAt == nil
            else {
                return nil
            }
            let taskRepository = SwiftDataTaskRepository(context: context)
            guard try taskRepository.directWorkTask(id: run.taskID) != nil else {
                return nil
            }
            let activeSegments = try timeRepository.activeSegments()
            let pomodoroRuns = try repository.runs()
            let plan = TimerAdmissionPolicy.startPlan(
                taskID: run.taskID,
                mode: allowParallelTimers ? .parallel : .exclusive,
                sameTaskBehavior: .replaceAll,
                activeSegments: activeSegments.map {
                    TimerActiveSegmentSnapshot(
                        segmentID: $0.id,
                        sessionID: $0.sessionID,
                        taskID: $0.taskID,
                        startedAt: $0.startedAt
                    )
                }
            )
            let segmentsToStop = plan.segmentsToStop.compactMap { planned in
                activeSegments.first { $0.id == planned.segmentID }
            }
            let stoppedSegments = segmentsToStop.map { segment in
                StoppedTimerMutationOutcome(
                    segmentID: segment.id,
                    sessionID: segment.sessionID,
                    taskID: segment.taskID
                )
            }

            let didResume = try repository.completeBreak(
                runID: run.id,
                expectedState: expectedState
            )
            guard didResume else { return nil }

            guard let resumedRun = try repository.run(id: run.id),
                  resumedRun.state == .focusing,
                  let resumedSessionID = resumedRun.sessionID,
                  let resumedSegment = try timeRepository.activeSegments().first(where: {
                      $0.sessionID == resumedSessionID && $0.taskID == resumedRun.taskID
                  })
            else {
                throw PomodoroCommandInvariantError.resumedLedgerSegmentMissing
            }

            for segment in segmentsToStop {
                try stopTimerSegment(
                    segment,
                    pomodoroRuns: pomodoroRuns,
                    timeRepository: timeRepository,
                    context: context
                )
            }
            guard segmentsToStop.allSatisfy({
                $0.endedAt != nil || $0.deletedAt != nil
            }) else {
                throw PomodoroCommandInvariantError.stoppedLedgerSegmentStillActive
            }
            return PomodoroBreakResumeOutcome(
                runID: resumedRun.id,
                taskID: resumedRun.taskID,
                resumedSessionID: resumedSessionID,
                resumedSegmentID: resumedSegment.id,
                stoppedSegments: stoppedSegments
            )
        }
        return try context.performAtomicMutation(mutation)
    }

    /// Stops one ledger segment after reconciling or cancelling the Pomodoro
    /// run that owns its session. An expired Pomodoro clips its session to
    /// the persisted phase deadline first; the idempotent segment stop then
    /// has nothing left to extend to the current wall clock.
    func stopTimerSegment(
        _ segment: TimeSegment,
        pomodoroRuns: [PomodoroRun],
        timeRepository: SwiftDataTimeTrackingRepository,
        context: ModelContext
    ) throws {
        try context.performAtomicMutation {
            try cancelIfNeeded(
                sessionID: segment.sessionID,
                runs: pomodoroRuns,
                context: context
            )
            try timeRepository.stopSegment(segmentID: segment.id)
        }
    }

    func cancelIfNeeded(
        sessionID: UUID,
        runs: [PomodoroRun],
        context: ModelContext,
        now: Date? = nil,
        discardShortAttempt: Bool = true
    ) throws {
        guard let run = runs.first(where: { $0.sessionID == sessionID && $0.deletedAt == nil && $0.endedAt == nil }) else {
            return
        }
        let mutationDate = nowProvider()
        let effectiveEndDate = now ?? mutationDate
        let mutation = {
            try cancelIfNeededMutation(
                run,
                sessionID: sessionID,
                context: context,
                effectiveEndDate: effectiveEndDate,
                mutationDate: mutationDate,
                discardShortAttempt: discardShortAttempt
            )
        }
        try context.performAtomicMutation(mutation)
    }

    private func cancelIfNeededMutation(
        _ run: PomodoroRun,
        sessionID: UUID,
        context: ModelContext,
        effectiveEndDate: Date,
        mutationDate: Date,
        discardShortAttempt: Bool
    ) throws {
        if try settleExpiredFocusIfNeeded(
            run,
            sessionID: sessionID,
            context: context,
            observedAt: effectiveEndDate,
            mutationDate: mutationDate
        ) {
            return
        }
        let shouldDiscard: Bool = if discardShortAttempt {
            try shouldDiscardCancelledRun(
                run,
                sessionID: sessionID,
                context: context,
                now: effectiveEndDate
            )
        } else {
            false
        }
        if shouldDiscard {
            try discardRunAndSession(
                run,
                sessionID: sessionID,
                context: context,
                effectiveEndDate: effectiveEndDate,
                mutationDate: mutationDate
            )
            return
        }
        run.state = .cancelled
        run.endedAt = run.startedAt.map { max(effectiveEndDate, $0) } ?? effectiveEndDate
        run.markMutated(at: mutationDate, deviceID: deviceID)
    }

    /// Deleting a ledger record is distinct from stopping it. Tombstone the
    /// corresponding Pomodoro regardless of elapsed time or phase deadline so
    /// the run cannot outlive the record the user explicitly removed.
    func discardIfNeeded(
        sessionID: UUID,
        runs: [PomodoroRun],
        context: ModelContext,
        now: Date? = nil
    ) throws {
        guard let run = runs.first(where: {
            $0.sessionID == sessionID &&
                $0.deletedAt == nil &&
                $0.endedAt == nil
        }) else {
            return
        }
        let mutationDate = nowProvider()
        let effectiveEndDate = now ?? mutationDate
        let mutation = {
            try discardRunAndSession(
                run,
                sessionID: sessionID,
                context: context,
                effectiveEndDate: effectiveEndDate,
                mutationDate: mutationDate
            )
        }
        try context.performAtomicMutation(mutation)
    }

    /// General timer commands can close a Pomodoro session without going
    /// through `SwiftDataPomodoroRepository`; settle an expired focus phase at
    /// its deadline exactly as that repository does.
    private func settleExpiredFocusIfNeeded(
        _ run: PomodoroRun,
        sessionID: UUID,
        context: ModelContext,
        observedAt: Date,
        mutationDate: Date
    ) throws -> Bool {
        guard run.state == .focusing || run.state == .interrupted,
              let deadline = run.phaseDeadline,
              deadline <= observedAt
        else {
            return false
        }
        let ledger = ledgerRepository(context)
        let phaseEndDate = try ledger.pomodoroPhaseEndDate(sessionID: sessionID, deadline: deadline)
        try ledger.endPomodoroSession(sessionID, at: phaseEndDate, mutationDate: mutationDate)
        run.completeFocusPhase(
            endedAt: phaseEndDate,
            mutationDate: mutationDate,
            deviceID: deviceID
        )
        return true
    }

    private func shouldDiscardCancelledRun(
        _ run: PomodoroRun,
        sessionID: UUID,
        context: ModelContext,
        now: Date
    ) throws -> Bool {
        let trackedSeconds = try ledgerRepository(context).pomodoroSessionTrackedSeconds(sessionID, now: now)
        return trackedSeconds < PomodoroRun.minimumKeptSeconds(focusSecondsPlanned: run.focusSecondsPlanned)
    }

    private func discardRunAndSession(
        _ run: PomodoroRun,
        sessionID: UUID,
        context: ModelContext,
        effectiveEndDate: Date,
        mutationDate: Date
    ) throws {
        run.state = .cancelled
        run.endedAt = run.startedAt.map { max(effectiveEndDate, $0) } ?? effectiveEndDate
        run.deletedAt = mutationDate
        run.markMutated(at: mutationDate, deviceID: deviceID)
        try ledgerRepository(context).discardPomodoroSession(
            sessionID,
            endedAt: effectiveEndDate,
            mutationDate: mutationDate
        )
    }

    private func ledgerRepository(_ context: ModelContext) -> SwiftDataTimeTrackingRepository {
        SwiftDataTimeTrackingRepository(context: context, deviceID: deviceID, nowProvider: nowProvider)
    }
}
