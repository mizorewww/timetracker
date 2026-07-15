import Foundation

struct ChecklistItemRecord: Codable, Equatable, SyncSnapshotRecord {
    let id: UUID
    let taskID: UUID
    let title: String
    let isCompleted: Bool
    let sortOrder: Double
    let completedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: ChecklistItem) {
        id = model.id
        taskID = model.taskID
        title = model.title
        isCompleted = model.isCompleted
        sortOrder = model.sortOrder
        completedAt = model.completedAt
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}

struct ChecklistItemVisualRecord: Codable, Equatable, SyncSnapshotRecord {
    let id: UUID
    let checklistItemID: UUID
    let iconName: String
    let colorHex: String
    let suggestionTitleSnapshot: String?
    let suggestionModelID: String?
    let suggestionGeneratedAt: Date?
    let userEditedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: ChecklistItemVisual) {
        id = model.id
        checklistItemID = model.checklistItemID
        iconName = model.iconName
        colorHex = model.colorHex
        suggestionTitleSnapshot = model.suggestionTitleSnapshot
        suggestionModelID = model.suggestionModelID
        suggestionGeneratedAt = model.suggestionGeneratedAt
        userEditedAt = model.userEditedAt
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}
