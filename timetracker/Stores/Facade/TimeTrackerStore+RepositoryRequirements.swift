import Foundation

extension TimeTrackerStore {
    @discardableResult
    func fail(_ error: StoreError) -> Bool {
        errorMessage = error.localizedDescription
        return false
    }

    func requiredTaskRepository() throws -> TaskRepository {
        guard let taskRepository else { throw StoreError.notConfigured }
        return taskRepository
    }

    func requiredTimeRepository() throws -> TimeTrackingRepository {
        guard let timeRepository else { throw StoreError.notConfigured }
        return timeRepository
    }

    func requiredPomodoroRepository() throws -> PomodoroRepository {
        guard let pomodoroRepository else { throw StoreError.notConfigured }
        return pomodoroRepository
    }

    enum StoreError: LocalizedError {
        case notConfigured
        case taskSelectionRequired
        case pomodoroTaskSelectionRequired
        case invalidTimeRange
        case activeTimerStartInFuture
        case closedSegmentCannotReopen
        case taskCategoryNameRequired
        case invalidInboxSuggestion
        case taskTrackingUnavailable

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
            case .activeTimerStartInFuture:
                Self.localized("segment.error.startNotFuture")
            case .closedSegmentCannotReopen:
                Self.localized("segment.error.cannotReopen")
            case .taskCategoryNameRequired:
                Self.localized("taskCategory.nameRequired")
            case .invalidInboxSuggestion:
                Self.localized("inbox.suggestion.error.noValidTask")
            case .taskTrackingUnavailable:
                Self.localized("task.archived.trackingUnavailable")
            }
        }

        private static func localized(_ key: String) -> String {
            NSLocalizedString(key, comment: "")
        }
    }
}
