import Foundation

protocol TaskRepository {
    func allNodes() throws -> [TaskNode]
    func rootNodes() throws -> [TaskNode]
    func children(of parentID: UUID?) throws -> [TaskNode]
    func task(id: UUID) throws -> TaskNode?
    func categories() throws -> [TaskCategory]
    func categoryAssignments() throws -> [TaskCategoryAssignment]
    func category(id: UUID) throws -> TaskCategory?
    func categoryID(forRootTaskID taskID: UUID) throws -> UUID?
    @discardableResult func createCategory(title: String, colorHex: String?, iconName: String?, includesInForecast: Bool) throws -> TaskCategory
    func updateCategory(categoryID: UUID, title: String, colorHex: String?, iconName: String?, includesInForecast: Bool) throws
    func softDeleteCategory(categoryID: UUID) throws
    @discardableResult func createTask(title: String, parentID: UUID?, categoryID: UUID?, colorHex: String?, iconName: String?) throws -> TaskNode
    func updateTask(taskID: UUID, title: String, status: TaskStatus, parentID: UUID?, categoryID: UUID?, colorHex: String?, iconName: String?, notes: String?, estimatedSeconds: Int?, dueAt: Date?) throws
    func moveTask(taskID: UUID, newParentID: UUID?, sortOrder: Double) throws
    func setTaskStatus(taskID: UUID, status: TaskStatus) throws
    func archiveTask(taskID: UUID) throws
    func softDeleteTask(taskID: UUID) throws
}

protocol TimeTrackingRepository {
    func activeSegments() throws -> [TimeSegment]
    func pausedSessions() throws -> [TimeSession]
    func sessions() throws -> [TimeSession]
    func segments(from: Date, to: Date) throws -> [TimeSegment]
    func segments(from: Date, to: Date, now: Date) throws -> [TimeSegment]
    func allSegments() throws -> [TimeSegment]
    @discardableResult func startTask(taskID: UUID, source: TimeSessionSource) throws -> TimeSegment
    func stopSegment(segmentID: UUID) throws
    func updateSegment(segmentID: UUID, taskID: UUID, startedAt: Date, endedAt: Date?, note: String?) throws
    func softDeleteSegment(segmentID: UUID) throws
    func stopSession(sessionID: UUID) throws
    func pauseSession(sessionID: UUID) throws
    @discardableResult func resumeSession(sessionID: UUID) throws -> TimeSegment?
    @discardableResult func addManualSegment(taskID: UUID, startedAt: Date, endedAt: Date, note: String?) throws -> TimeSegment
}

protocol PomodoroRepository {
    func runs() throws -> [PomodoroRun]
    func activeRuns() throws -> [PomodoroRun]
    @discardableResult func startPomodoro(taskID: UUID, focusSeconds: Int, breakSeconds: Int, targetRounds: Int) throws -> PomodoroRun
    func completeFocus(runID: UUID) throws
    func cancel(runID: UUID) throws
}

enum TaskRepositoryError: LocalizedError, Equatable {
    case invalidMove

    var errorDescription: String? {
        AppStrings.localized("task.error.invalidMove")
    }
}
