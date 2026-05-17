import Foundation

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
        perform(event: .pomodoroChanged(runID: nil, sessionID: nil, taskID: selectedTaskID)) {
            _ = try pomodoroCommandHandler.start(
                taskID: selectedTaskID,
                focusSeconds: focusSeconds,
                breakSeconds: breakSeconds,
                longBreakSeconds: longBreakSeconds,
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
        let discardRecord = shouldDiscardCancelledPomodoro(run)
        perform(event: .pomodoroChanged(runID: run.id, sessionID: run.sessionID, taskID: run.taskID)) {
            try pomodoroCommandHandler.cancel(
                run: run,
                discardRecord: discardRecord,
                repository: requiredPomodoroRepository()
            )
        }
    }

    private func shouldDiscardCancelledPomodoro(_ run: PomodoroRun, now: Date = Date()) -> Bool {
        let segmentSeconds = pomodoroElapsedFocusSeconds(for: run, now: now)
        let fallbackSeconds = run.startedAt.map { max(0, Int(now.timeIntervalSince($0))) } ?? 0
        let effectiveSeconds = max(segmentSeconds, fallbackSeconds)
        return effectiveSeconds < Int(Double(max(1, run.focusSecondsPlanned)) * 0.2)
    }
}
