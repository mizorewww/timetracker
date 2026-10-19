import Foundation
import SwiftData

extension TimeTrackerStore {
    func startSelectedTask() throws {
        guard let selectedTaskID else { return }
        try startTask(taskID: selectedTaskID)
    }

    @discardableResult
    func startTask(_ task: TaskNode) throws -> Bool {
        let didStart = try startTask(taskID: task.id)
        if didStart {
            selectTask(task.id, revealInToday: false)
        }
        return didStart
    }

    @discardableResult
    func startTask(
        taskID: UUID,
        source: TimeSessionSource = .timer
    ) throws -> Bool {
        try performStoreCommand(
            command: { session in
                try StoreScopedTimerCommandCoordinator(session: session)
                    .start(taskID: taskID, source: source)
            },
            finishResult: finishStoreScopedTimerCommand
        )
    }

    var timerPickerMode: TimerPickerMode {
        guard activeSegments.isEmpty == false else { return .start }
        return preferences.allowParallelTimers ? .startAnother : .switchTimer
    }

    func timerPickerSelectionCommand(for task: TaskNode) -> TimerPickerSelectionCommand {
        guard activeSegment(for: task.id) == nil else { return .alreadyRunning }
        return timerPickerMode == .switchTimer ? .switchTimer : .start
    }

    @discardableResult
    func performTimerPickerSelection(_ task: TaskNode) throws -> TimerPickerSelectionOutcome {
        let command = timerPickerSelectionCommand(for: task)
        guard command != .alreadyRunning else { return .alreadyRunning }
        guard try startTask(task) else { return .failed }
        return command == .switchTimer ? .switched : .started
    }

    @discardableResult
    func stop(segment: TimeSegment) throws -> Bool {
        try stopTimer(segmentID: segment.id)
    }

    @discardableResult
    func stopTimer(
        segmentID: UUID? = nil,
        taskID: UUID? = nil
    ) throws -> Bool {
        try performStoreCommand(
            command: { session in
                try StoreScopedTimerCommandCoordinator(session: session)
                    .stop(segmentID: segmentID, taskID: taskID)
            },
            finishResult: finishStoreScopedTimerCommand
        )
    }
}
