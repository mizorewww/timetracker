import Foundation

nonisolated struct PomodoroPhaseToken: Hashable, Sendable {
    let runID: UUID
    let stateRaw: String
    let mutationID: UUID

    @MainActor
    init(run: PomodoroRun) {
        self.init(
            runID: run.id,
            stateRaw: run.stateRaw,
            mutationID: run.clientMutationID
        )
    }

    init(runID: UUID, stateRaw: String, mutationID: UUID) {
        self.runID = runID
        self.stateRaw = stateRaw
        self.mutationID = mutationID
    }
}

nonisolated struct PomodoroRunMutationSnapshot: Hashable, Sendable {
    let runID: UUID
    let taskID: UUID
    let sessionID: UUID?

    @MainActor
    init(run: PomodoroRun) {
        runID = run.id
        taskID = run.taskID
        sessionID = run.sessionID
    }
}

nonisolated struct PomodoroFocusMutationSnapshot: Hashable, Sendable {
    let runID: UUID
    let taskID: UUID
    let sessionID: UUID
    let segmentID: UUID
    let phaseToken: PomodoroPhaseToken
}

nonisolated struct StoreScopedPomodoroStartOutcome: Hashable, Sendable {
    let startedFocus: PomodoroFocusMutationSnapshot
    let stoppedSegments: [TimerMutationSegmentSnapshot]
    let settledRuns: [PomodoroRunMutationSnapshot]

    var referencedTaskIDs: Set<UUID> {
        Set(stoppedSegments.map(\.taskID))
            .union(settledRuns.map(\.taskID))
            .union([startedFocus.taskID])
    }

    @MainActor
    var events: Set<StoreDomainEvent> {
        var events = Self.events(
            for: startedFocus.taskID,
            sessionID: startedFocus.sessionID,
            runID: startedFocus.runID
        )
        for segment in stoppedSegments {
            events.formUnion(
                Self.events(
                    for: segment.taskID,
                    sessionID: segment.sessionID,
                    runID: nil
                )
            )
        }
        for run in settledRuns {
            events.insert(
                .pomodoroChanged(
                    runID: run.runID,
                    sessionID: run.sessionID,
                    taskID: run.taskID
                )
            )
        }
        return events
    }

    @MainActor
    private static func events(
        for taskID: UUID,
        sessionID: UUID,
        runID: UUID?
    ) -> Set<StoreDomainEvent> {
        [
            .ledgerChanged(taskID: taskID, dateInterval: nil, isVisible: true),
            .pomodoroChanged(runID: runID, sessionID: sessionID, taskID: taskID),
        ]
    }
}

nonisolated enum StoreScopedPomodoroResumeRejection: Hashable, Sendable {
    case stalePhase
    case taskUnavailable(UUID)
}

nonisolated struct StoreScopedPomodoroResumeMutation: Hashable, Sendable {
    let resumedFocus: PomodoroFocusMutationSnapshot
    let stoppedSegments: [TimerMutationSegmentSnapshot]

    var referencedTaskIDs: Set<UUID> {
        Set(stoppedSegments.map(\.taskID)).union([resumedFocus.taskID])
    }

    @MainActor
    var events: Set<StoreDomainEvent> {
        var events: Set<StoreDomainEvent> = [
            .ledgerChanged(
                taskID: resumedFocus.taskID,
                dateInterval: nil,
                isVisible: true
            ),
            .pomodoroChanged(
                runID: resumedFocus.runID,
                sessionID: resumedFocus.sessionID,
                taskID: resumedFocus.taskID
            ),
        ]
        for segment in stoppedSegments {
            events.insert(
                .ledgerChanged(
                    taskID: segment.taskID,
                    dateInterval: nil,
                    isVisible: true
                )
            )
            events.insert(
                .pomodoroChanged(
                    runID: nil,
                    sessionID: segment.sessionID,
                    taskID: segment.taskID
                )
            )
        }
        return events
    }
}

nonisolated enum StoreScopedPomodoroResumeOutcome: Hashable, Sendable {
    case resumed(StoreScopedPomodoroResumeMutation)
    case rejected(StoreScopedPomodoroResumeRejection)
}
