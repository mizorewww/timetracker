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
        guard let modelContext else {
            errorMessage = StoreError.notConfigured.localizedDescription
            return false
        }
        do {
            let outcome = try StoreScopedPomodoroCommandCoordinator(
                container: modelContext.container,
                writeAuthorization: writeAuthorization
            ).start(
                taskID: taskID,
                focusSeconds: focusSeconds,
                breakSeconds: breakSeconds,
                longBreakSeconds: longBreakSeconds,
                targetRounds: targetRounds
            )
            finishStoreScopedPomodoroMutation(
                events: outcome.events,
                referencedTaskIDs: outcome.referencedTaskIDs
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func resumeActivePomodoroAfterBreak(
        phase: PomodoroPhaseToken
    ) -> Bool {
        guard let modelContext else {
            errorMessage = StoreError.notConfigured.localizedDescription
            return false
        }
        do {
            let outcome = try StoreScopedPomodoroCommandCoordinator(
                container: modelContext.container,
                writeAuthorization: writeAuthorization
            ).resume(
                phase: phase
            )
            switch outcome {
            case .resumed(let mutation):
                finishStoreScopedPomodoroMutation(
                    events: mutation.events,
                    referencedTaskIDs: mutation.referencedTaskIDs
                )
                return true
            case .rejected:
                refreshStoreScopedPomodoroAdmissionReadModels()
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
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
            errorMessage = String(
                format: AppStrings.localized("error.savedRefreshFailed"),
                missingTaskRefreshError.localizedDescription
            )
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
            errorMessage = String(
                format: AppStrings.localized("error.savedRefreshFailed"),
                error.localizedDescription
            )
        }
    }
}
