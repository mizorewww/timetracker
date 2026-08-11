import Foundation

extension SwiftDataPomodoroRepository {
    @discardableResult
    func completeFocus(runID: UUID, endedAt: Date = Date()) throws -> Bool {
        guard let run = try run(id: runID) else { return false }
        return try completeFocus(
            runID: runID,
            expectedState: run.state,
            endedAt: endedAt
        )
    }

    @discardableResult
    func completeBreak(runID: UUID) throws -> Bool {
        guard let run = try run(id: runID) else { return false }
        return try completeBreak(runID: runID, expectedState: run.state)
    }

    func cancel(runID: UUID) throws {
        try cancel(runID: runID, discardRecord: false)
    }
}

enum TaskRepositoryError: LocalizedError, Equatable {
    case invalidMove
    case categoryUnavailable
    case appleHealthPlacementLocked

    var errorDescription: String? {
        switch self {
        case .invalidMove:
            AppStrings.localized("task.error.invalidMove")
        case .categoryUnavailable:
            AppStrings.localized("taskCategory.error.unavailable")
        case .appleHealthPlacementLocked:
            AppStrings.localized("task.error.appleHealthPlacementLocked")
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
