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

struct InboxCaptureReceiptRecord: Codable, Equatable, SyncSnapshotRecord {
    let id: UUID
    let commandKey: String
    let payloadFingerprint: String
    let inboxItemID: UUID
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: InboxCaptureReceipt) {
        id = model.id
        commandKey = model.commandKey
        payloadFingerprint = model.payloadFingerprint
        inboxItemID = model.inboxItemID
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}

struct InboxSuggestionRecord: Codable, Equatable, SyncSnapshotRecord {
    let id: UUID
    let inboxItemID: UUID
    let inboxItemContextID: UUID?
    let inboxItemRevisionID: UUID?
    let taskID: UUID
    let destinationKindRaw: String
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
        destinationKindRaw = model.destinationKindRaw
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

    private enum CodingKeys: String, CodingKey {
        case id
        case inboxItemID
        case inboxItemContextID
        case inboxItemRevisionID
        case taskID
        case destinationKindRaw
        case reason
        case iconName
        case colorHex
        case modelID
        case titleSnapshot
        case generatedAt
        case createdAt
        case updatedAt
        case deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        inboxItemID = try container.decode(UUID.self, forKey: .inboxItemID)
        inboxItemContextID = try container.decodeIfPresent(UUID.self, forKey: .inboxItemContextID)
        inboxItemRevisionID = try container.decodeIfPresent(UUID.self, forKey: .inboxItemRevisionID)
        taskID = try container.decode(UUID.self, forKey: .taskID)
        destinationKindRaw = if container.contains(.destinationKindRaw) {
            try container.decode(String.self, forKey: .destinationKindRaw)
        } else {
            InboxSuggestionDestinationKind.checklist.rawValue
        }
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        iconName = try container.decode(String.self, forKey: .iconName)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        modelID = try container.decodeIfPresent(String.self, forKey: .modelID)
        titleSnapshot = try container.decode(String.self, forKey: .titleSnapshot)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}
