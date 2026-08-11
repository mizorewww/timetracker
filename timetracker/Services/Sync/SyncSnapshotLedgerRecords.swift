import Foundation

nonisolated struct TimeSessionRecord:
    Codable,
    Equatable,
    SyncSnapshotRecord
{
    let id: UUID
    let taskID: UUID
    let titleSnapshot: String?
    let sourceRaw: String
    let startedAt: Date
    let endedAt: Date?
    let note: String?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: TimeSession) {
        id = model.id
        taskID = model.taskID
        titleSnapshot = model.titleSnapshot
        sourceRaw = model.sourceRaw
        startedAt = model.startedAt
        endedAt = model.endedAt
        note = model.note
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}

nonisolated struct TimeSegmentRecord:
    Codable,
    Equatable,
    SyncSnapshotRecord
{
    let id: UUID
    let sessionID: UUID
    let taskID: UUID
    let startedAt: Date
    let endedAt: Date?
    let sourceRaw: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: TimeSegment) {
        id = model.id
        sessionID = model.sessionID
        taskID = model.taskID
        startedAt = model.startedAt
        endedAt = model.endedAt
        sourceRaw = model.sourceRaw
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}

nonisolated struct PomodoroRunRecord:
    Codable,
    Equatable,
    SyncSnapshotRecord
{
    let id: UUID
    let taskID: UUID
    let sessionID: UUID?
    let focusSecondsPlanned: Int
    let breakSecondsPlanned: Int
    let longBreakSecondsPlanned: Int?
    let stateRaw: String
    let startedAt: Date?
    let endedAt: Date?
    let completedFocusRounds: Int
    let targetRounds: Int
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: PomodoroRun) {
        id = model.id
        taskID = model.taskID
        sessionID = model.sessionID
        focusSecondsPlanned = model.focusSecondsPlanned
        breakSecondsPlanned = model.breakSecondsPlanned
        longBreakSecondsPlanned = model.longBreakSecondsPlanned
        stateRaw = model.stateRaw
        startedAt = model.startedAt
        endedAt = model.endedAt
        completedFocusRounds = model.completedFocusRounds
        targetRounds = model.targetRounds
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}
