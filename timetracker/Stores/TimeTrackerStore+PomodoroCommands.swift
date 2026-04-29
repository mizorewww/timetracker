import Foundation

extension TimeTrackerStore {
    func startPomodoroForSelectedTask(focusSeconds: Int = 25 * 60, breakSeconds: Int = 5 * 60, targetRounds: Int = 1) {
        guard let selectedTaskID else {
            errorMessage = AppStrings.localized("task.selectBeforePomodoro")
            return
        }
        perform(event: .pomodoroChanged(runID: nil, sessionID: nil, taskID: selectedTaskID)) {
            _ = try pomodoroCommandHandler.start(
                taskID: selectedTaskID,
                focusSeconds: focusSeconds,
                breakSeconds: breakSeconds,
                targetRounds: targetRounds,
                allowParallelTimers: preferences.allowParallelTimers,
                activeSegments: activeSegments,
                pomodoroRuns: pomodoroRuns,
                timeRepository: requiredTimeRepository(),
                pomodoroRepository: requiredPomodoroRepository(),
                context: modelContext
            )
        }
    }

    func completeActivePomodoro() {
        guard let run = activePomodoroRun else { return }
        perform(event: .pomodoroChanged(runID: run.id, sessionID: run.sessionID, taskID: run.taskID)) {
            try pomodoroCommandHandler.complete(run: run, repository: requiredPomodoroRepository())
        }
    }

    func cancelActivePomodoro() {
        guard let run = activePomodoroRun else { return }
        perform(event: .pomodoroChanged(runID: run.id, sessionID: run.sessionID, taskID: run.taskID)) {
            try pomodoroCommandHandler.cancel(run: run, repository: requiredPomodoroRepository())
        }
    }
}
