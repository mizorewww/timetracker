import Foundation

struct InboxItemRecord: Codable, Equatable, SyncSnapshotRecord {
    let id: UUID
    let title: String
    let notes: String?
    let isCompleted: Bool
    let sortOrder: Double
    let completedAt: Date?
    let suggestedTaskID: UUID?
    let suggestionReason: String?
    let suggestionGeneratedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: InboxItem) {
        id = model.id
        title = model.title
        notes = model.notes
        isCompleted = model.isCompleted
        sortOrder = model.sortOrder
        completedAt = model.completedAt
        suggestedTaskID = model.suggestedTaskID
        suggestionReason = model.suggestionReason
        suggestionGeneratedAt = model.suggestionGeneratedAt
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}

struct InboxSuggestionRecord: Codable, Equatable, SyncSnapshotRecord {
    let id: UUID
    let inboxItemID: UUID
    let taskID: UUID
    let reason: String?
    let iconName: String
    let colorHex: String
    let modelID: String?
    let titleSnapshot: String
    let generatedAt: Date
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: InboxSuggestion) {
        id = model.id
        inboxItemID = model.inboxItemID
        taskID = model.taskID
        reason = model.reason
        iconName = model.iconName
        colorHex = model.colorHex
        modelID = model.modelID
        titleSnapshot = model.titleSnapshot
        generatedAt = model.generatedAt
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}
