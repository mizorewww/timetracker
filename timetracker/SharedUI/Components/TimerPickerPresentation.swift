import SwiftUI

extension TimerPickerMode {
    var title: String {
        switch self {
        case .start:
            AppStrings.startTimer
        case .startAnother:
            AppStrings.localized("home.startAnotherTimer")
        case .switchTimer:
            AppStrings.localized("home.switchTimer")
        }
    }

    var systemImage: String {
        switch self {
        case .start:
            "play.fill"
        case .startAnother:
            "plus"
        case .switchTimer:
            "arrow.left.arrow.right"
        }
    }

    /// The Today primary action deliberately uses the existing
    /// "Start Another Timer" visual grammar for every timer-picker mode.
    var primaryActionSystemImage: String {
        switch self {
        case .start, .startAnother:
            "plus.circle"
        case .switchTimer:
            "arrow.left.arrow.right.circle"
        }
    }

    var footer: LocalizedStringKey {
        switch self {
        case .start:
            .app("timer.picker.startFooter")
        case .startAnother:
            .app("timer.picker.parallelFooter")
        case .switchTimer:
            .app("timer.picker.switchFooter")
        }
    }
}

extension TimerPickerSelectionCommand {
    var actionTitle: String {
        switch self {
        case .alreadyRunning:
            AppStrings.running
        case .start:
            AppStrings.localized("timer.picker.action.start")
        case .switchTimer:
            AppStrings.localized("timer.picker.action.switch")
        }
    }

    var systemImage: String {
        switch self {
        case .alreadyRunning:
            "checkmark"
        case .start:
            "play.fill"
        case .switchTimer:
            "arrow.left.arrow.right"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .alreadyRunning:
            AppStrings.localized("timer.picker.runningHint")
        case .start:
            AppStrings.localized("timer.task.startHint")
        case .switchTimer:
            AppStrings.localized("timer.task.switchHint")
        }
    }

    func accessibilityLabel(for taskTitle: String) -> String {
        let key = switch self {
        case .alreadyRunning:
            "timer.picker.runningTaskFormat"
        case .start:
            "timer.picker.startTaskFormat"
        case .switchTimer:
            "timer.picker.switchTaskFormat"
        }
        return String(format: AppStrings.localized(key), taskTitle)
    }
}
