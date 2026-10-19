import Foundation
import SwiftData

extension TimeTrackerStore {
    func startSelectedTask() {
        guard let selectedTaskID else { return }
        _ = startTask(taskID: selectedTaskID)
    }

    @discardableResult
    func startTask(_ task: TaskNode) -> Bool {
        let didStart = startTask(taskID: task.id)
        if didStart {
            selectTask(task.id, revealInToday: false)
        }
        return didStart
    }

    @discardableResult
    func startTask(
        taskID: UUID,
        source: TimeSessionSource = .timer
    ) -> Bool {
        performStoreCommand(
            command: { container in
                try SystemActionCommandHandler(
                    writeAuthorization: writeAuthorization
                ).startTimerMutation(
                    taskID: taskID,
                    source: source,
                    container: container
                )
            },
            finishResult: finishStoreScopedTimerCommand
        ) ?? false
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
    func performTimerPickerSelection(_ task: TaskNode) -> TimerPickerSelectionOutcome {
        let command = timerPickerSelectionCommand(for: task)
        guard command != .alreadyRunning else { return .alreadyRunning }
        guard startTask(task) else { return .failed }
        return command == .switchTimer ? .switched : .started
    }

    @discardableResult
    func stop(segment: TimeSegment) -> Bool {
        stopTimer(segmentID: segment.id)
    }

    @discardableResult
    func stopTimer(
        segmentID: UUID? = nil,
        taskID: UUID? = nil
    ) -> Bool {
        performStoreCommand(
            command: { container in
                try SystemActionCommandHandler(
                    writeAuthorization: writeAuthorization
                ).stopTimerMutation(
                    segmentID: segmentID,
                    taskID: taskID,
                    container: container
                )
            },
            finishResult: finishStoreScopedTimerCommand
        ) ?? false
    }
}
