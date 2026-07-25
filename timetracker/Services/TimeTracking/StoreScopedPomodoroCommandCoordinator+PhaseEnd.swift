import Foundation
import SwiftData

private enum StoreScopedPomodoroPhaseEndInvariantError: Error {
    case focusCompletionMissing
    case cancellationMissing
    case reconciliationMissing
}

extension StoreScopedPomodoroCommandCoordinator {
    func complete(
        phase: PomodoroPhaseToken
    ) throws -> StoreScopedPomodoroPhaseMutationOutcome {
        try withLockedFreshContext { _, now, _, pomodoroRepository in
            guard let run = try matchingRun(
                phase: phase,
                allowedStates: [.focusing, .interrupted],
                repository: pomodoroRepository
            ) else {
                return .rejected(.stalePhase)
            }
            let sessionIDBefore = run.sessionID
            guard try PomodoroCommandHandler(
                deviceID: resolvedDeviceID,
                nowProvider: { now }
            ).completeFocus(
                runID: run.id,
                expectedState: run.state,
                repository: pomodoroRepository
            ),
                run.clientMutationID != phase.mutationID,
                run.sessionID == nil,
                run.state == .shortBreak || run.state == .longBreak || run.state == .completed
            else {
                throw StoreScopedPomodoroPhaseEndInvariantError.focusCompletionMissing
            }
            return .mutated(
                phaseEndSnapshot(
                    run: run,
                    previousPhase: phase,
                    sessionIDBefore: sessionIDBefore
                )
            )
        }
    }

    func cancel(
        phase: PomodoroPhaseToken
    ) throws -> StoreScopedPomodoroPhaseMutationOutcome {
        try withLockedFreshContext { _, now, timeRepository, pomodoroRepository in
            guard let run = try matchingRun(
                phase: phase,
                allowedStates: [.planned, .focusing, .interrupted, .shortBreak, .longBreak],
                repository: pomodoroRepository
            ) else {
                return .rejected(.stalePhase)
            }
            let sessionIDBefore = run.sessionID
            let discardRecord = try shouldDiscardCancelledRun(
                run,
                now: now,
                timeRepository: timeRepository
            )
            try PomodoroCommandHandler(
                deviceID: resolvedDeviceID,
                nowProvider: { now }
            ).cancel(
                run: run,
                discardRecord: discardRecord,
                repository: pomodoroRepository
            )
            guard run.clientMutationID != phase.mutationID,
                  run.endedAt != nil,
                  run.state == .cancelled || run.state == .completed,
                  discardRecord == false || run.deletedAt != nil
            else {
                throw StoreScopedPomodoroPhaseEndInvariantError.cancellationMissing
            }
            return .mutated(
                phaseEndSnapshot(
                    run: run,
                    previousPhase: phase,
                    sessionIDBefore: sessionIDBefore
                )
            )
        }
    }

    func reconcileExpiredFocuses(
        observedAt: Date
    ) throws -> StoreScopedPomodoroReconcileOutcome {
        try withLockedFreshContext { _, mutationNow, _, pomodoroRepository in
            let candidates = try pomodoroRepository.activeRuns().filter { run in
                (run.state == .focusing || run.state == .interrupted) &&
                    run.phaseHasExpired(at: observedAt)
            }
            var mutations: [PomodoroPhaseEndMutationSnapshot] = []
            for run in candidates {
                let previousPhase = PomodoroPhaseToken(run: run)
                let sessionIDBefore = run.sessionID
                guard try PomodoroCommandHandler(
                    deviceID: resolvedDeviceID,
                    nowProvider: { mutationNow }
                ).reconcile(
                    run: run,
                    now: observedAt,
                    repository: pomodoroRepository
                ),
                    run.clientMutationID != previousPhase.mutationID,
                    run.sessionID == nil,
                    run.state == .shortBreak || run.state == .longBreak || run.state == .completed
                else {
                    throw StoreScopedPomodoroPhaseEndInvariantError.reconciliationMissing
                }
                mutations.append(
                    phaseEndSnapshot(
                        run: run,
                        previousPhase: previousPhase,
                        sessionIDBefore: sessionIDBefore
                    )
                )
            }
            return StoreScopedPomodoroReconcileOutcome(mutations: mutations)
        }
    }

    private var resolvedDeviceID: String {
        deviceID ?? DeviceIdentity.current
    }

    private func withLockedFreshContext<Result>(
        _ operation: (
            ModelContext,
            Date,
            SwiftDataTimeTrackingRepository,
            SwiftDataPomodoroRepository
        ) throws -> Result
    ) throws -> Result {
        try writeAuthorization.requireUserWritesAllowed()
        let scope = try TimerStoreScope(container: container)
        let transaction = StoreScopedTimerMutationTransaction(
            scope: scope,
            container: container
        )
        return try transaction.withFreshContext { context in
            let now = nowProvider()
            let timeRepository = SwiftDataTimeTrackingRepository(
                context: context,
                deviceID: resolvedDeviceID,
                nowProvider: { now }
            )
            let pomodoroRepository = SwiftDataPomodoroRepository(
                context: context,
                timeRepository: timeRepository,
                deviceID: resolvedDeviceID,
                nowProvider: { now }
            )
            return try operation(context, now, timeRepository, pomodoroRepository)
        }
    }

    private func matchingRun(
        phase: PomodoroPhaseToken,
        allowedStates: Set<PomodoroState>,
        repository: SwiftDataPomodoroRepository
    ) throws -> PomodoroRun? {
        guard let run = try repository.run(id: phase.runID),
              run.stateRaw == phase.stateRaw,
              run.clientMutationID == phase.mutationID,
              allowedStates.contains(run.state),
              run.deletedAt == nil,
              run.endedAt == nil
        else {
            return nil
        }
        return run
    }

    private func shouldDiscardCancelledRun(
        _ run: PomodoroRun,
        now: Date,
        timeRepository: SwiftDataTimeTrackingRepository
    ) throws -> Bool {
        guard run.completedFocusRounds == 0,
              run.state == .focusing || run.state == .interrupted
        else {
            return false
        }
        let segments = try timeRepository.allSegments().filter { segment in
            segment.sessionID == run.sessionID &&
                segment.source == .pomodoro &&
                segment.deletedAt == nil
        }
        let segmentSeconds = TimeAggregationService().grossSeconds(segments, now: now)
        let fallbackSeconds = run.startedAt.map {
            max(0, Int(now.timeIntervalSince($0)))
        } ?? 0
        let effectiveSeconds = max(segmentSeconds, fallbackSeconds)
        return effectiveSeconds < Int(Double(max(1, run.focusSecondsPlanned)) * 0.2)
    }

    private func phaseEndSnapshot(
        run: PomodoroRun,
        previousPhase: PomodoroPhaseToken,
        sessionIDBefore: UUID?
    ) -> PomodoroPhaseEndMutationSnapshot {
        PomodoroPhaseEndMutationSnapshot(
            previousPhase: previousPhase,
            taskID: run.taskID,
            sessionIDBefore: sessionIDBefore,
            resultingStateRaw: run.stateRaw,
            resultingMutationID: run.clientMutationID,
            discardedRecord: run.deletedAt != nil
        )
    }
}
