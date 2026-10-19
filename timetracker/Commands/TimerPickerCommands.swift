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
