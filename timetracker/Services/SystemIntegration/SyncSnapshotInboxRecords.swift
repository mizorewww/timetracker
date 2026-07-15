import Foundation

struct InboxItemRecord: Codable, Equatable, SyncSnapshotRecord {
    let id: UUID
    let suggestionContextID: UUID?
    let suggestionRevisionID: UUID?
    let dismissedSuggestionRevisionID: UUID?
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
        self.init(
            model,
            mergedDismissedSuggestionRevisionID: model.dismissedSuggestionRevisionID
        )
    }

    init(
        _ model: InboxItem,
        mergedDismissedSuggestionRevisionID: UUID?
    ) {
        id = model.id
        suggestionContextID = model.effectiveSuggestionContextID
        suggestionRevisionID = model.effectiveSuggestionRevisionID
        dismissedSuggestionRevisionID = mergedDismissedSuggestionRevisionID
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

extension InboxItemRecord {
    var effectiveSuggestionIdentity: InboxSuggestionIdentity {
        InboxSuggestionIdentity(
            contextID: suggestionContextID ?? id,
            revisionID: suggestionRevisionID ?? id
        )
    }

    func isPreferredLogicalWinner(over other: Self) -> Bool {
        if (deletedAt == nil) != (other.deletedAt == nil) {
            if updatedAt != other.updatedAt {
                return updatedAt > other.updatedAt
            }
            return deletedAt != nil
        }
        if updatedAt != other.updatedAt {
            return updatedAt > other.updatedAt
        }
        if createdAt != other.createdAt {
            return createdAt > other.createdAt
        }
        return id.uuidString > other.id.uuidString
    }
}

struct InboxSuggestionRecord: Codable, Equatable, SyncSnapshotRecord {
    let id: UUID
    let inboxItemID: UUID
    let inboxItemContextID: UUID?
    let inboxItemRevisionID: UUID?
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
        inboxItemContextID = model.inboxItemContextID
        inboxItemRevisionID = model.inboxItemRevisionID
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
