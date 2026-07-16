import Foundation

extension TimeTrackerStore {
    func startSelectedTask() {
        guard let selectedTaskID else { return }
        _ = startTask(taskID: selectedTaskID)
    }

    @discardableResult
    func startTask(_ task: TaskNode) -> Bool {
        guard isTaskAvailableForTracking(task) else {
            errorMessage = AppStrings.localized("systemAction.error.taskNotFound")
            return false
        }
        selectTask(task.id, revealInToday: false)
        return startTask(taskID: task.id)
    }

    @discardableResult
    private func startTask(taskID: UUID) -> Bool {
        guard let task = task(for: taskID), isTaskAvailableForTracking(task) else {
            errorMessage = AppStrings.localized("systemAction.error.taskNotFound")
            return false
        }
        return perform(events: timerStartMutationEvents(taskID: taskID)) {
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

    var timerPickerMode: TimerPickerMode {
        TimerPickerCommandPolicy().mode(
            hasActiveTimers: activeSegments.isEmpty == false,
            allowParallelTimers: preferences.allowParallelTimers
        )
    }

    func timerPickerSelectionCommand(for task: TaskNode) -> TimerPickerSelectionCommand {
        TimerPickerCommandPolicy().selectionCommand(
            isTaskRunning: activeSegment(for: task.id) != nil,
            mode: timerPickerMode
        )
    }

    @discardableResult
    func performTimerPickerSelection(_ task: TaskNode) -> TimerPickerSelectionOutcome {
        switch timerPickerSelectionCommand(for: task) {
        case .alreadyRunning:
            return .alreadyRunning
        case .start:
            return startTask(task) ? .started : .failed
        case .switchTimer:
            return startTask(task) ? .switched : .failed
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
