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
        timeRepository: TimeTrackingRepository,
        pomodoroRepository: PomodoroRepository,
        context: ModelContext?
    ) throws -> PomodoroRun {
        let mutation = { () throws -> PomodoroRun in
            if allowParallelTimers == false {
                try TimerCommandHandler(
                    deviceID: deviceID,
                    nowProvider: nowProvider
                ).stopOtherActiveSegments(
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
        if let context {
            return try context.performAtomicMutation(mutation)
        }
        return try mutation()
    }

    @discardableResult
    func completeFocus(
        runID: UUID,
        expectedState: PomodoroState,
        repository: PomodoroRepository
    ) throws -> Bool {
        guard expectedState == .focusing || expectedState == .interrupted else {
            return false
        }
        return try CompletePomodoroFocusUseCase(repository: repository).execute(
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
        timeRepository: TimeTrackingRepository,
        repository: PomodoroRepository,
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
            let admission = TimerStartAdmissionPolicy().evaluate(
                taskID: run.taskID,
                allowParallelTimers: allowParallelTimers,
                activeSegments: activeSegments,
                existingTaskAdmission: .replaceExisting
            )
            guard admission.shouldStartNewSegment else { return nil }
            let stoppedSegments = admission.segmentsToStop.map { segment in
                StoppedTimerMutationOutcome(
                    segmentID: segment.id,
                    sessionID: segment.sessionID,
                    taskID: segment.taskID
                )
            }

            let didResume = try CompletePomodoroBreakUseCase(repository: repository).execute(
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

            let timerHandler = TimerCommandHandler(
                deviceID: deviceID,
                nowProvider: nowProvider
            )
            for segment in admission.segmentsToStop {
                try timerHandler.stop(
                    segment: segment,
                    pomodoroRuns: pomodoroRuns,
                    timeRepository: timeRepository,
                    context: context
                )
            }
            guard admission.segmentsToStop.allSatisfy({
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

    @discardableResult
    func reconcile(run: PomodoroRun, now: Date, repository: PomodoroRepository) throws -> Bool {
        try repository.reconcileExpiredPhase(runID: run.id, now: now)
    }

    func cancel(run: PomodoroRun, discardRecord: Bool = false, repository: PomodoroRepository) throws {
        try CancelPomodoroUseCase(repository: repository).execute(runID: run.id, discardRecord: discardRecord)
    }

    func cancelIfNeeded(
        sessionID: UUID,
        runs: [PomodoroRun],
        context: ModelContext?,
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
        if let context {
            try context.performAtomicMutation(mutation)
        } else {
            try mutation()
        }
    }

    private func cancelIfNeededMutation(
        _ run: PomodoroRun,
        sessionID: UUID,
        context: ModelContext?,
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
        context: ModelContext?,
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
        if let context {
            try context.performAtomicMutation(mutation)
        } else {
            try mutation()
        }
    }

    /// General timer commands can close a Pomodoro session without going
    /// through `PomodoroRepository`. Preserve the same deadline semantics here
    /// so a stop from a widget, Watch, deep link, or ledger edit cannot record
    /// suspension time as focus time or incorrectly cancel a completed round.
    private func settleExpiredFocusIfNeeded(
        _ run: PomodoroRun,
        sessionID: UUID,
        context: ModelContext?,
        observedAt: Date,
        mutationDate: Date
    ) throws -> Bool {
        guard run.state == .focusing || run.state == .interrupted,
              let deadline = run.phaseDeadline,
              deadline <= observedAt
        else {
            return false
        }

        let sessionSegments = try context.map { try segments(in: sessionID, context: $0) } ?? []
        let phaseEndDate = max(
            deadline,
            sessionSegments
                .filter { $0.deletedAt == nil }
                .map(\.startedAt)
                .max() ?? deadline
        )
        for segment in sessionSegments where segment.deletedAt == nil {
            if segment.endedAt.map({ $0 > phaseEndDate }) ?? true {
                segment.endedAt = max(segment.startedAt, phaseEndDate)
                segment.updatedAt = mutationDate
                segment.deviceID = deviceID
            }
        }

        if let context,
           let session = try session(id: sessionID, context: context),
           session.deletedAt == nil
        {
            let latestEnd = sessionSegments
                .filter { $0.deletedAt == nil }
                .compactMap(\.endedAt)
                .max() ?? phaseEndDate
            session.endedAt = max(session.startedAt, latestEnd)
            session.markMutated(at: mutationDate, deviceID: deviceID)
        }

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
            return total + TrackedTimePolicy.elapsedSeconds(
                startedAt: segment.startedAt,
                endedAt: segment.endedAt,
                now: now
            )
        }
    }

    private func discardRunAndSession(
        _ run: PomodoroRun,
        sessionID: UUID,
        context: ModelContext?,
        effectiveEndDate: Date,
        mutationDate: Date
    ) throws {
        run.state = .cancelled
        run.endedAt = run.startedAt.map { max(effectiveEndDate, $0) } ?? effectiveEndDate
        run.deletedAt = mutationDate
        run.markMutated(at: mutationDate, deviceID: deviceID)

        guard let context else { return }
        let sessionSegments = try segments(in: sessionID, context: context)
        for segment in sessionSegments {
            segment.endedAt = max(segment.startedAt, segment.endedAt ?? effectiveEndDate)
            segment.deletedAt = mutationDate
            segment.updatedAt = mutationDate
            segment.deviceID = deviceID
        }
        if let session = try session(id: sessionID, context: context) {
            let latestSegmentEnd = sessionSegments.compactMap(\.endedAt).max() ?? effectiveEndDate
            session.endedAt = max(session.startedAt, session.endedAt ?? latestSegmentEnd)
            session.deletedAt = mutationDate
            session.markMutated(at: mutationDate, deviceID: deviceID)
        }
    }

    private func segments(in sessionID: UUID, context: ModelContext) throws -> [TimeSegment] {
        let targetSessionID = sessionID
        let descriptor = FetchDescriptor<TimeSegment>(
            predicate: #Predicate { $0.sessionID == targetSessionID },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return try context.fetch(descriptor)
            .visibleDeduplicatedByID()
            .filter { $0.sessionID == targetSessionID }
    }

    private func session(id: UUID, context: ModelContext) throws -> TimeSession? {
        let sessionID = id
        let descriptor = FetchDescriptor<TimeSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        return try context.fetch(descriptor).visibleDeduplicatedByID().first
    }
}
