import Foundation

extension SwiftDataPomodoroRepository {
    func cancel(runID: UUID) throws {
        try cancel(runID: runID, discardRecord: false)
    }
}

enum TaskRepositoryError: LocalizedError, Equatable {
    case invalidMove
    case categoryUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidMove:
            AppStrings.localized("task.error.invalidMove")
        case .categoryUnavailable:
            AppStrings.localized("taskCategory.error.unavailable")
        }
    }
}

enum TimeTrackingRepositoryError: LocalizedError, Equatable {
    case invalidTimeRange
    case futureTime
    case taskUnavailable
    case closedSegmentCannotReopen

    var errorDescription: String? {
        switch self {
        case .invalidTimeRange:
            AppStrings.localized("time.endAfterStart")
        case .futureTime:
            AppStrings.localized("segment.error.timeNotFuture")
        case .taskUnavailable:
            AppStrings.localized("task.archived.trackingUnavailable")
        case .closedSegmentCannotReopen:
            AppStrings.localized("segment.error.cannotReopen")
        }
    }
}
