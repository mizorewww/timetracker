import Foundation
import SwiftData

private enum StoreScopedPomodoroCommandInvariantError: Error {
    case startedFocusMissing
    case resumedFocusMissing
    case breakSessionStillOpen
}

/// Serializes Pomodoro admission and phase changes with ordinary timer commands
/// and task lifecycle writes for one concrete SwiftData store.
@MainActor
struct StoreScopedPomodoroCommandCoordinator {
    let container: ModelContainer
    let writeAuthorization: StoreWriteAuthorization
    let deviceID: String?
    let nowProvider: () -> Date

    init(
        container: ModelContainer,
        writeAuthorization: StoreWriteAuthorization = .applicationState,
        deviceID: String? = nil,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.container = container
        self.writeAuthorization = writeAuthorization
        self.deviceID = deviceID
        self.nowProvider = nowProvider
    }

    func start(
        taskID: UUID,
        focusSeconds: Int,
        breakSeconds: Int,
        longBreakSeconds: Int?,
        targetRounds: Int
    ) throws -> StoreScopedPomodoroStartOutcome {
        try writeAuthorization.requireUserWritesAllowed()
        let scope = try TimerStoreScope(container: container)
        let transaction = StoreScopedTimerMutationTransaction(
            scope: scope,
            container: container
        )

        return try transaction.withFreshContext { context in
            let now = nowProvider()
            let resolvedDeviceID = deviceID ?? DeviceIdentity.current
            let taskRepository = SwiftDataTaskRepository(
                context: context,
                deviceID: resolvedDeviceID
            )
            let tasks = try taskRepository.allNodes()
            guard try TaskTrackingAvailabilityService()
                .directWorkTaskIDs(
                    tasks: tasks,
                    recurrenceRules: taskRepository.taskRecurrenceRules(),
                    recurrenceOccurrences:
                    taskRepository.taskRecurrenceOccurrences()
                )
                .contains(taskID)
            else {
                throw SystemActionCommandError.taskNotFound
            }
            let allowParallelTimers = try TimerAdmissionPreferenceResolver
                .allowParallelTimers(in: context)

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
            let activeSegmentsBefore = try timeRepository.activeSegments()
            let activeRunsBefore = try pomodoroRepository.activeRuns()
            let settledRuns = activeRunsBefore.map(PomodoroRunMutationSnapshot.init)

            let startedRun = try PomodoroCommandHandler(
                deviceID: resolvedDeviceID,
                nowProvider: { now }
            ).start(
                taskID: taskID,
                focusSeconds: focusSeconds,
                breakSeconds: breakSeconds,
                longBreakSeconds: longBreakSeconds,
                targetRounds: targetRounds,
                allowParallelTimers: allowParallelTimers,
                activeSegments: activeSegmentsBefore,
                pomodoroRuns: pomodoroRepository.runs(),
                timeRepository: timeRepository,
                pomodoroRepository: pomodoroRepository,
                context: context
            )

            let activeSegmentsAfter = try timeRepository.activeSegments()
            let activeSegmentIDsAfter = Set(activeSegmentsAfter.map(\.id))
            let stoppedSegments = activeSegmentsBefore
                .filter { activeSegmentIDsAfter.contains($0.id) == false }
                .map(TimerMutationSegmentSnapshot.init)
            guard startedRun.state == .focusing,
                  let sessionID = startedRun.sessionID,
                  let segment = activeSegmentsAfter.first(where: {
                      $0.sessionID == sessionID && $0.taskID == startedRun.taskID
                  }),
                  try pomodoroRepository.activeRuns().map(\.id) == [startedRun.id]
            else {
                throw StoreScopedPomodoroCommandInvariantError.startedFocusMissing
            }
            let focus = PomodoroFocusMutationSnapshot(
                runID: startedRun.id,
                taskID: startedRun.taskID,
                sessionID: sessionID,
                segmentID: segment.id,
                phaseToken: PomodoroPhaseToken(run: startedRun)
            )
            return StoreScopedPomodoroStartOutcome(
                startedFocus: focus,
                stoppedSegments: stoppedSegments,
                settledRuns: settledRuns
            )
        }
    }

    func resume(
        phase: PomodoroPhaseToken
    ) throws -> StoreScopedPomodoroResumeOutcome {
        try writeAuthorization.requireUserWritesAllowed()
        let scope = try TimerStoreScope(container: container)
        let transaction = StoreScopedTimerMutationTransaction(
            scope: scope,
            container: container
        )

        return try transaction.withFreshContext { context in
            let now = nowProvider()
            let resolvedDeviceID = deviceID ?? DeviceIdentity.current
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
            guard let run = try pomodoroRepository.run(id: phase.runID),
                  run.stateRaw == phase.stateRaw,
                  run.clientMutationID == phase.mutationID,
                  run.state == .shortBreak || run.state == .longBreak,
                  run.deletedAt == nil,
                  run.endedAt == nil
            else {
                return .rejected(.stalePhase)
            }
            guard run.sessionID == nil else {
                throw StoreScopedPomodoroCommandInvariantError.breakSessionStillOpen
            }

            let taskRepository = SwiftDataTaskRepository(
                context: context,
                deviceID: resolvedDeviceID
            )
            let tasks = try taskRepository.allNodes()
            guard try TaskTrackingAvailabilityService()
                .directWorkTaskIDs(
                    tasks: tasks,
                    recurrenceRules: taskRepository.taskRecurrenceRules(),
                    recurrenceOccurrences:
                    taskRepository.taskRecurrenceOccurrences()
                )
                .contains(run.taskID)
            else {
                return .rejected(.taskUnavailable(run.taskID))
            }
            let allowParallelTimers = try TimerAdmissionPreferenceResolver
                .allowParallelTimers(in: context)

            guard let outcome = try PomodoroCommandHandler(
                deviceID: resolvedDeviceID,
                nowProvider: { now }
            ).resumeFocusAfterBreak(
                runID: run.id,
                expectedState: run.state,
                allowParallelTimers: allowParallelTimers,
                timeRepository: timeRepository,
                repository: pomodoroRepository,
                context: context
            ),
                let resumedRun = try pomodoroRepository.run(id: run.id),
                resumedRun.state == .focusing,
                resumedRun.clientMutationID != phase.mutationID
            else {
                throw StoreScopedPomodoroCommandInvariantError.resumedFocusMissing
            }
            let focus = PomodoroFocusMutationSnapshot(
                runID: resumedRun.id,
                taskID: resumedRun.taskID,
                sessionID: outcome.resumedSessionID,
                segmentID: outcome.resumedSegmentID,
                phaseToken: PomodoroPhaseToken(run: resumedRun)
            )
            return .resumed(
                StoreScopedPomodoroResumeMutation(
                    resumedFocus: focus,
                    stoppedSegments: outcome.stoppedSegments.map {
                        TimerMutationSegmentSnapshot(
                            segmentID: $0.segmentID,
                            sessionID: $0.sessionID,
                            taskID: $0.taskID
                        )
                    }
                )
            )
        }
    }
}
