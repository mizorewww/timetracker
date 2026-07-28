import Foundation

nonisolated struct TaskRecurrenceRuleRecord:
    Codable,
    Equatable,
    SyncSnapshotRecord
{
    let id: UUID
    let templateTaskID: UUID
    let cadenceRaw: String
    let startDayKey: String
    let timeZoneIdentifier: String
    let isEnabled: Bool
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: TaskRecurrenceRule) {
        id = model.id
        templateTaskID = model.templateTaskID
        cadenceRaw = model.cadenceRaw
        startDayKey = model.startDayKey
        timeZoneIdentifier = model.timeZoneIdentifier
        isEnabled = model.isEnabled
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}

nonisolated struct TaskRecurrenceOccurrenceRecord:
    Codable,
    Equatable,
    SyncSnapshotRecord
{
    let id: UUID
    let ruleID: UUID
    let templateTaskID: UUID
    let occurrenceDayKey: String
    let timeZoneIdentifier: String
    let generatedTaskID: UUID
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: TaskRecurrenceOccurrence) {
        id = model.id
        ruleID = model.ruleID
        templateTaskID = model.templateTaskID
        occurrenceDayKey = model.occurrenceDayKey
        timeZoneIdentifier = model.timeZoneIdentifier
        generatedTaskID = model.generatedTaskID
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}

nonisolated struct TaskQuantityGoalRecord:
    Codable,
    Equatable,
    SyncSnapshotRecord
{
    let id: UUID
    let taskID: UUID
    let targetAmount: Int
    let unitLabel: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: TaskQuantityGoal) {
        id = model.id
        taskID = model.taskID
        targetAmount = model.targetAmount
        unitLabel = model.unitLabel
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}

nonisolated struct TaskQuantityEntryRecord:
    Codable,
    Equatable,
    SyncSnapshotRecord
{
    let id: UUID
    let taskID: UUID
    let quantityGoalID: UUID
    let amount: Int
    let recordedAt: Date
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: TaskQuantityEntry) {
        id = model.id
        taskID = model.taskID
        quantityGoalID = model.quantityGoalID
        amount = model.amount
        recordedAt = model.recordedAt
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}
