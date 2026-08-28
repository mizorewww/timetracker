import Foundation
import SwiftData

extension TimeTrackerStore {
    func startPomodoroForSelectedTask(
        focusSeconds: Int = 25 * 60,
        breakSeconds: Int = 5 * 60,
        longBreakSeconds: Int? = nil,
        targetRounds: Int = 1
    ) {
        guard let selectedTaskID else {
            fail(.pomodoroTaskSelectionRequired)
            return
        }
        _ = startPomodoro(
            taskID: selectedTaskID,
            focusSeconds: focusSeconds,
            breakSeconds: breakSeconds,
            longBreakSeconds: longBreakSeconds,
            targetRounds: targetRounds
        )
    }

    @discardableResult
    func startPomodoro(
        taskID: UUID,
        focusSeconds: Int = 25 * 60,
        breakSeconds: Int = 5 * 60,
        longBreakSeconds: Int? = nil,
        targetRounds: Int = 1
    ) -> Bool {
        performStoreCommand(
            command: { container in
                try StoreScopedPomodoroCommandCoordinator(
                    container: container,
                    writeAuthorization: writeAuthorization
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
        ) != nil
    }

    @discardableResult
    func resumeActivePomodoroAfterBreak(
        phase: PomodoroPhaseToken
    ) -> Bool {
        performStoreCommand(
            command: { container in
                try StoreScopedPomodoroCommandCoordinator(
                    container: container,
                    writeAuthorization: writeAuthorization
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
        ) ?? false
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
            errorMessage = savedRefreshFailedMessage(missingTaskRefreshError)
        }
    }

    func refreshStoreScopedPomodoroAdmissionReadModels() {
        do {
            try refresh(
                plan: StoreRefreshPlan(
                    scopes: [.tasks, .ledgerVisible, .pomodoro]
                )
            )
        } catch {
            errorMessage = savedRefreshFailedMessage(error)
        }
    }
}
