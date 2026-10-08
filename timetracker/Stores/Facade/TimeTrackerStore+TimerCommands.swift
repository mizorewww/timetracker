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
            .alreadyRunning
        case .start:
            startTask(task) ? .started : .failed
        case .switchTimer:
            startTask(task) ? .switched : .failed
        }
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
