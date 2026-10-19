import Foundation

extension TimeTrackerStore {
    enum StoreError: LocalizedError {
        case notConfigured
        case taskSelectionRequired
        case pomodoroTaskSelectionRequired
        case invalidTimeRange
        case taskCategoryNameRequired
        case invalidInboxSuggestion
        case taskTrackingUnavailable
        case llmConfigurationIncomplete

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                "TimeTrackerStore has not been configured with a ModelContext."
            case .taskSelectionRequired:
                Self.localized("task.selectRequired")
            case .pomodoroTaskSelectionRequired:
                Self.localized("task.selectBeforePomodoro")
            case .invalidTimeRange:
                Self.localized("time.endAfterStart")
            case .taskCategoryNameRequired:
                Self.localized("taskCategory.nameRequired")
            case .invalidInboxSuggestion:
                Self.localized("inbox.suggestion.error.noValidTask")
            case .taskTrackingUnavailable:
                Self.localized("task.archived.trackingUnavailable")
            case .llmConfigurationIncomplete:
                Self.localized("settings.llm.needsSetup")
            }
        }

        private static func localized(_ key: String) -> String {
            NSLocalizedString(key, comment: "")
        }
    }
}
