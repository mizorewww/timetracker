import Foundation

struct StartTaskUseCase {
    let repository: TimeTrackingRepository

    @discardableResult
    func execute(taskID: UUID, source: TimeSessionSource = .timer) throws -> TimeSegment {
        try repository.startTask(taskID: taskID, source: source)
    }
}

struct StopSegmentUseCase {
    let repository: TimeTrackingRepository

    func execute(segmentID: UUID) throws {
        try repository.stopSegment(segmentID: segmentID)
    }
}

struct UpdateSegmentUseCase {
    let repository: TimeTrackingRepository

    func execute(segmentID: UUID, taskID: UUID, startedAt: Date, endedAt: Date?, note: String?) throws {
        try repository.updateSegment(
            segmentID: segmentID,
            taskID: taskID,
            startedAt: startedAt,
            endedAt: endedAt,
            note: note
        )
    }
}

struct SoftDeleteSegmentUseCase {
    let repository: TimeTrackingRepository

    func execute(segmentID: UUID) throws {
        try repository.softDeleteSegment(segmentID: segmentID)
    }
}

struct StopSessionUseCase {
    let repository: TimeTrackingRepository

    func execute(sessionID: UUID) throws {
        try repository.stopSession(sessionID: sessionID)
    }
}

struct PauseSessionUseCase {
    let repository: TimeTrackingRepository

    func execute(sessionID: UUID) throws {
        try repository.pauseSession(sessionID: sessionID)
    }
}

struct ResumeSessionUseCase {
    let repository: TimeTrackingRepository

    @discardableResult
    func execute(sessionID: UUID) throws -> TimeSegment? {
        try repository.resumeSession(sessionID: sessionID)
    }
}

struct AddManualTimeUseCase {
    let repository: TimeTrackingRepository

    @discardableResult
    func execute(taskID: UUID, startedAt: Date, endedAt: Date, note: String?) throws -> TimeSegment {
        try repository.addManualSegment(taskID: taskID, startedAt: startedAt, endedAt: endedAt, note: note)
    }
}

struct UpdateTaskUseCase {
    let repository: TaskRepository

    func execute(
        taskID: UUID,
        title: String,
        kind: TaskNodeKind,
        parentID: UUID?,
        colorHex: String?,
        iconName: String?,
        notes: String?,
        estimatedSeconds: Int?,
        dueAt: Date?
    ) throws {
        try repository.updateTask(
            taskID: taskID,
            title: title,
            kind: kind,
            parentID: parentID,
            colorHex: colorHex,
            iconName: iconName,
            notes: notes,
            estimatedSeconds: estimatedSeconds,
            dueAt: dueAt
        )
    }
}

struct ArchiveTaskUseCase {
    let repository: TaskRepository

    func execute(taskID: UUID) throws {
        try repository.archiveTask(taskID: taskID)
    }
}

struct SoftDeleteTaskUseCase {
    let repository: TaskRepository

    func execute(taskID: UUID) throws {
        try repository.softDeleteTask(taskID: taskID)
    }
}

struct CreateTaskUseCase {
    let repository: TaskRepository

    @discardableResult
    func execute(title: String, kind: TaskNodeKind = .task, parentID: UUID? = nil, colorHex: String? = nil, iconName: String? = nil) throws -> TaskNode {
        try repository.createTask(title: title, kind: kind, parentID: parentID, colorHex: colorHex, iconName: iconName)
    }
}

struct MoveTaskUseCase {
    let repository: TaskRepository

    func execute(taskID: UUID, newParentID: UUID?, sortOrder: Double) throws {
        try repository.moveTask(taskID: taskID, newParentID: newParentID, sortOrder: sortOrder)
    }
}

struct StartPomodoroUseCase {
    let repository: PomodoroRepository

    @discardableResult
    func execute(taskID: UUID, focusSeconds: Int = 25 * 60, breakSeconds: Int = 5 * 60, targetRounds: Int = 1) throws -> PomodoroRun {
        try repository.startPomodoro(taskID: taskID, focusSeconds: focusSeconds, breakSeconds: breakSeconds, targetRounds: targetRounds)
    }
}

struct CompletePomodoroFocusUseCase {
    let repository: PomodoroRepository

    func execute(runID: UUID) throws {
        try repository.completeFocus(runID: runID)
    }
}

struct CancelPomodoroUseCase {
    let repository: PomodoroRepository

    func execute(runID: UUID) throws {
        try repository.cancel(runID: runID)
    }
}
