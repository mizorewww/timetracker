import Foundation
import SwiftData

extension TimeTrackerStore {
    func startPomodoroForSelectedTask(
        focusSeconds: Int = 25 * 60,
        breakSeconds: Int = 5 * 60,
        longBreakSeconds: Int? = nil,
        targetRounds: Int = 1
    ) throws {
        guard let selectedTaskID else {
            throw StoreError.pomodoroTaskSelectionRequired
        }
        try startPomodoro(
            taskID: selectedTaskID,
            focusSeconds: focusSeconds,
            breakSeconds: breakSeconds,
            longBreakSeconds: longBreakSeconds,
            targetRounds: targetRounds
        )
    }

    func startPomodoro(
        taskID: UUID,
        focusSeconds: Int = 25 * 60,
        breakSeconds: Int = 5 * 60,
        longBreakSeconds: Int? = nil,
        targetRounds: Int = 1
    ) throws {
        try performStoreCommand(
            command: { session in
                try StoreScopedPomodoroCommandCoordinator(
                    session: session
                ).start(
                    taskID: taskID,
                    focusSeconds: focusSeconds,
                    breakSeconds: breakSeconds,
                    longBreakSeconds: longBreakSeconds,
                    targetRounds: targetRounds
                )
            },
            finish: { outcome in
                finishStoreScopedPomodoroMutation(
                    events: outcome.events,
                    referencedTaskIDs: outcome.referencedTaskIDs
                )
            }
        )
    }

    @discardableResult
    func resumeActivePomodoroAfterBreak(
        phase: PomodoroPhaseToken
    ) throws -> Bool {
        try performStoreCommand(
            command: { session in
                try StoreScopedPomodoroCommandCoordinator(
                    session: session
                ).resume(
                    phase: phase
                )
            },
            finishResult: { outcome in
                switch outcome {
                case let .resumed(mutation):
                    finishStoreScopedPomodoroMutation(
                        events: mutation.events,
                        referencedTaskIDs: mutation.referencedTaskIDs
                    )
                    return true
                case .rejected:
                    refreshStoreScopedPomodoroAdmissionReadModels()
                    return false
                }
            }
        )
    }

    func finishStoreScopedPomodoroMutation(
        events: Set<StoreDomainEvent>,
        referencedTaskIDs: Set<UUID>
    ) {
        var missingTaskRefreshError: Error?
        if referencedTaskIDs.contains(where: { taskByID[$0] == nil }) {
            do {
                try refresh(plan: StoreRefreshPlan(scopes: [.tasks]))
            } catch {
                missingTaskRefreshError = error
            }
        }
        finishStoreScopedMutation(events: events)
        if let missingTaskRefreshError {
            logReadModelRefreshFailure(missingTaskRefreshError)
        }
    }

    func refreshStoreScopedPomodoroAdmissionReadModels() {
        refreshLoggingFailure(
            plan: StoreRefreshPlan(
                scopes: [.tasks, .ledgerVisible, .pomodoro]
            )
        )
    }
}
