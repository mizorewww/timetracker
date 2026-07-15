import Foundation

extension TimeTrackerStore {
    func startSelectedTask() {
        guard let selectedTaskID else { return }
        startTask(taskID: selectedTaskID)
    }

    func startTask(_ task: TaskNode) {
        guard isTaskAvailableForTracking(task) else {
            errorMessage = AppStrings.localized("systemAction.error.taskNotFound")
            return
        }
        selectTask(task.id, revealInToday: false)
        startTask(taskID: task.id)
    }

    private func startTask(taskID: UUID) {
        guard let task = task(for: taskID), isTaskAvailableForTracking(task) else {
            errorMessage = AppStrings.localized("systemAction.error.taskNotFound")
            return
        }
        perform(events: timerStartMutationEvents(taskID: taskID)) {
            try timerCommandHandler.startTask(
                taskID: taskID,
                allowParallelTimers: preferences.allowParallelTimers,
                activeSegments: activeSegments,
                pomodoroRuns: pomodoroRuns,
                timeRepository: requiredTimeRepository(),
                context: modelContext
            )
        }
    }

    func stop(segment: TimeSegment) {
        perform(events: timerStopMutationEvents(segment: segment)) {
            try timerCommandHandler.stop(segment: segment, pomodoroRuns: pomodoroRuns, timeRepository: requiredTimeRepository(), context: modelContext)
        }
    }

    func timerStartMutationEvents(taskID: UUID) -> Set<StoreDomainEvent> {
        var events: Set<StoreDomainEvent> = [
            .ledgerChanged(taskID: taskID, dateInterval: nil, isVisible: true),
            .pomodoroChanged(runID: nil, sessionID: nil, taskID: taskID)
        ]
        guard preferences.allowParallelTimers == false else { return events }

        for segment in activeSegments where segment.taskID != taskID {
            events.formUnion(timerStopMutationEvents(segment: segment))
        }
        return events
    }

    func timerStopMutationEvents(segment: TimeSegment) -> Set<StoreDomainEvent> {
        timerStopMutationEvents(taskID: segment.taskID, sessionID: segment.sessionID)
    }

    func timerStopMutationEvents(taskID: UUID, sessionID: UUID) -> Set<StoreDomainEvent> {
        [
            .ledgerChanged(taskID: taskID, dateInterval: nil, isVisible: true),
            .pomodoroChanged(runID: nil, sessionID: sessionID, taskID: taskID)
        ]
    }
}
