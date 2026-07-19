import Foundation

protocol TaskRepository {
    @discardableResult func repairInvalidHierarchy() throws -> Set<UUID>
    func allNodes() throws -> [TaskNode]
    func rootNodes() throws -> [TaskNode]
    func children(of parentID: UUID?) throws -> [TaskNode]
    func task(id: UUID) throws -> TaskNode?
    func tasks(ids: Set<UUID>) throws -> [TaskNode]
    func categories() throws -> [TaskCategory]
    func categoryAssignments() throws -> [TaskCategoryAssignment]
    func category(id: UUID) throws -> TaskCategory?
    func categoryID(forRootTaskID taskID: UUID) throws -> UUID?
    @discardableResult func createCategory(title: String, colorHex: String?, iconName: String?, includesInForecast: Bool) throws -> TaskCategory
    func updateCategory(categoryID: UUID, title: String, colorHex: String?, iconName: String?, includesInForecast: Bool) throws
    func softDeleteCategory(categoryID: UUID) throws
    @discardableResult func createTask(title: String, parentID: UUID?, categoryID: UUID?, colorHex: String?, iconName: String?) throws -> TaskNode
    func updateTask(taskID: UUID, title: String, parentID: UUID?, categoryID: UUID?, colorHex: String?, iconName: String?, notes: String?, estimatedSeconds: Int?, dueAt: Date?) throws
    func moveTask(taskID: UUID, newParentID: UUID?, sortOrder: Double) throws
    func archiveTask(taskID: UUID) throws
    func unarchiveTask(taskID: UUID) throws
    func softDeleteTask(taskID: UUID) throws
}

extension TaskRepository {
    @discardableResult
    func repairInvalidHierarchy() throws -> Set<UUID> { [] }
}

protocol TimeTrackingRepository {
    func activeSegments() throws -> [TimeSegment]
    func sessions() throws -> [TimeSession]
    func sessions(ids: Set<UUID>) throws -> [TimeSession]
    func segments(ids: Set<UUID>) throws -> [TimeSegment]
    func segments(from: Date, to: Date) throws -> [TimeSegment]
    func segments(from: Date, to: Date, now: Date) throws -> [TimeSegment]
    func allSegments() throws -> [TimeSegment]
    @discardableResult func startTask(taskID: UUID, source: TimeSessionSource) throws -> TimeSegment
    func stopSegment(segmentID: UUID) throws
    func updateSegment(segmentID: UUID, taskID: UUID, startedAt: Date, endedAt: Date?, note: String?) throws
    func softDeleteSegment(segmentID: UUID) throws
    func stopSession(sessionID: UUID) throws
    @discardableResult func addManualSegment(taskID: UUID, startedAt: Date, endedAt: Date, note: String?) throws -> TimeSegment
}

extension TimeTrackingRepository {
    func segments(ids: Set<UUID>) throws -> [TimeSegment] {
        guard ids.isEmpty == false else { return [] }
        return try allSegments().filter { ids.contains($0.id) }
    }
}

protocol PomodoroRepository {
    func run(id: UUID) throws -> PomodoroRun?
    func runs() throws -> [PomodoroRun]
    func activeRuns() throws -> [PomodoroRun]
    @discardableResult func startPomodoro(taskID: UUID, focusSeconds: Int, breakSeconds: Int, longBreakSeconds: Int?, targetRounds: Int) throws -> PomodoroRun
    @discardableResult func completeFocus(
        runID: UUID,
        expectedState: PomodoroState,
        endedAt: Date
    ) throws -> Bool
    @discardableResult func completeBreak(
        runID: UUID,
        expectedState: PomodoroState
    ) throws -> Bool
    func cancel(runID: UUID, discardRecord: Bool) throws
    @discardableResult func reconcileExpiredPhase(runID: UUID, now: Date) throws -> Bool
}

extension PomodoroRepository {
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
