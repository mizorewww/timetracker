import Foundation
import SwiftData

extension SyncDataSnapshot {
    func restoreInboxItems(context: ModelContext, now: Date, deviceID: String) throws {
        var existing = try context.fetch(FetchDescriptor<InboxItem>())
            .latestByIDMarkingDuplicatesDeleted(now: now, deviceID: deviceID)
        let snapshotIDs = Set(inboxItems.map(\.id))
        for item in existing.values where !snapshotIDs.contains(item.id) {
            item.deletedAt = now
            item.updatedAt = now
            item.deviceID = deviceID
            item.clientMutationID = UUID()
        }
        for record in inboxItems {
            let model = existing[record.id] ?? InboxItem(
                title: record.title,
                isCompleted: record.isCompleted,
                sortOrder: record.sortOrder,
                deviceID: deviceID
            )
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            model.id = record.id
            model.title = record.title
            model.notes = record.notes
            model.isCompleted = record.isCompleted
            model.sortOrder = record.sortOrder
            model.completedAt = record.completedAt
            model.suggestedTaskID = record.suggestedTaskID
            model.suggestionReason = record.suggestionReason
            model.suggestionGeneratedAt = record.suggestionGeneratedAt
            model.createdAt = record.createdAt
            model.updatedAt = max(record.updatedAt, now)
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            model.clientMutationID = UUID()
        }
    }

    func restoreInboxSuggestions(context: ModelContext, now: Date, deviceID: String) throws {
        var existing = try context.fetch(FetchDescriptor<InboxSuggestion>())
            .latestByIDMarkingDuplicatesDeleted(now: now, deviceID: deviceID)
        let snapshotIDs = Set(inboxSuggestions.map(\.id))
        for suggestion in existing.values where !snapshotIDs.contains(suggestion.id) {
            suggestion.deletedAt = now
            suggestion.updatedAt = now
            suggestion.deviceID = deviceID
            suggestion.clientMutationID = UUID()
        }
        for record in inboxSuggestions {
            let model = existing[record.id] ?? InboxSuggestion(
                inboxItemID: record.inboxItemID,
                taskID: record.taskID,
                reason: record.reason,
                iconName: record.iconName,
                colorHex: record.colorHex,
                modelID: record.modelID,
                titleSnapshot: record.titleSnapshot,
                generatedAt: record.generatedAt,
                deviceID: deviceID
            )
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            model.id = record.id
            model.inboxItemID = record.inboxItemID
            model.taskID = record.taskID
            model.reason = record.reason
            model.iconName = record.iconName
            model.colorHex = record.colorHex
            model.modelID = record.modelID
            model.titleSnapshot = record.titleSnapshot
            model.generatedAt = record.generatedAt
            model.createdAt = record.createdAt
            model.updatedAt = max(record.updatedAt, now)
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            model.clientMutationID = UUID()
        }
    }
}
