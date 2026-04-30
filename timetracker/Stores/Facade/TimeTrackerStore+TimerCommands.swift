import Foundation

extension TimeTrackerStore {
    func startSelectedTask() {
        guard let selectedTaskID else { return }
        startTask(taskID: selectedTaskID)
    }

    func selectTask(_ taskID: UUID, revealInToday: Bool = true) {
        selectedTaskID = taskID
        if revealInToday {
            desktopDestination = .today
        }
        selectedTaskPulseID = taskID
        selectedTaskPulseToken = UUID()
    }

    func startTask(_ task: TaskNode) {
        selectTask(task.id, revealInToday: false)
        startTask(taskID: task.id)
    }

    private func startTask(taskID: UUID) {
        perform(event: .ledgerChanged(taskID: taskID, dateInterval: nil, isVisible: true)) {
            try timerCommandHandler.startTask(
                taskID: taskID,
                allowParallelTimers: preferences.allowParallelTimers,
                activeSegments: activeSegments,
                pausedSessions: pausedSessions,
                pomodoroRuns: pomodoroRuns,
                timeRepository: requiredTimeRepository(),
                context: modelContext
            )
        }
    }

    func stop(segment: TimeSegment) {
        perform(event: .ledgerChanged(taskID: segment.taskID, dateInterval: nil, isVisible: true)) {
            try timerCommandHandler.stop(segment: segment, pomodoroRuns: pomodoroRuns, timeRepository: requiredTimeRepository(), context: modelContext)
        }
    }

    func pause(segment: TimeSegment) {
        perform(event: .ledgerChanged(taskID: segment.taskID, dateInterval: nil, isVisible: true)) {
            try timerCommandHandler.pause(segment: segment, pomodoroRuns: pomodoroRuns, timeRepository: requiredTimeRepository(), context: modelContext)
        }
    }

    func resume(session: TimeSession) {
        perform(event: .ledgerChanged(taskID: session.taskID, dateInterval: nil, isVisible: true)) {
            try timerCommandHandler.resume(session: session, pomodoroRuns: pomodoroRuns, timeRepository: requiredTimeRepository(), context: modelContext)
        }
    }

    func stop(session: TimeSession) {
        perform(event: .ledgerChanged(taskID: session.taskID, dateInterval: nil, isVisible: true)) {
            try timerCommandHandler.stop(session: session, pomodoroRuns: pomodoroRuns, timeRepository: requiredTimeRepository(), context: modelContext)
        }
    }
}
