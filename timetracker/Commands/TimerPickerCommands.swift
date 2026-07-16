import Foundation

enum TimerPickerMode: Equatable {
    case start
    case startAnother
    case switchTimer
}

enum TimerPickerSelectionCommand: Equatable {
    case alreadyRunning
    case start
    case switchTimer
}

enum TimerPickerSelectionOutcome: Equatable {
    case alreadyRunning
    case started
    case switched
    case failed

    var shouldDismissPicker: Bool {
        self == .started || self == .switched
    }
}

struct TimerPickerCommandPolicy {
    func mode(
        hasActiveTimers: Bool,
        allowParallelTimers: Bool
    ) -> TimerPickerMode {
        guard hasActiveTimers else { return .start }
        return allowParallelTimers ? .startAnother : .switchTimer
    }

    func selectionCommand(
        isTaskRunning: Bool,
        mode: TimerPickerMode
    ) -> TimerPickerSelectionCommand {
        guard isTaskRunning == false else { return .alreadyRunning }
        return mode == .switchTimer ? .switchTimer : .start
    }
}
