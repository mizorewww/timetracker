import Foundation
import SwiftData

extension SyncDataSnapshot {
    func restoreChecklistItems(context: ModelContext, now: Date, deviceID: String) throws {
        var existing = try context.fetch(FetchDescriptor<ChecklistItem>())
            .latestByIDMarkingDuplicatesDeleted(now: now, deviceID: deviceID)
        let snapshotIDs = Set(checklistItems.map(\.id))
        for item in existing.values where !snapshotIDs.contains(item.id) {
            item.deletedAt = now
            item.updatedAt = now
            item.deviceID = deviceID
            item.clientMutationID = UUID()
        }
        for record in checklistItems {
            let model = existing[record.id] ?? ChecklistItem(
                taskID: record.taskID,
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
            model.taskID = record.taskID
            model.title = record.title
            model.isCompleted = record.isCompleted
            model.sortOrder = record.sortOrder
            model.completedAt = record.completedAt
            model.createdAt = record.createdAt
            model.updatedAt = max(record.updatedAt, now)
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            model.clientMutationID = UUID()
        }
    }

    func restoreChecklistItemVisuals(
        context: ModelContext,
        now: Date,
        deviceID: String
    ) throws {
        var existing = try context.fetch(FetchDescriptor<ChecklistItemVisual>())
            .latestByIDMarkingDuplicatesDeleted(now: now, deviceID: deviceID)
        let snapshotIDs = Set(checklistItemVisuals.map(\.id))
        for visual in existing.values where !snapshotIDs.contains(visual.id) {
            visual.deletedAt = now
            visual.updatedAt = now
            visual.deviceID = deviceID
            visual.clientMutationID = UUID()
        }
        for record in checklistItemVisuals {
            let model = existing[record.id] ?? ChecklistItemVisual(
                checklistItemID: record.checklistItemID,
                iconName: record.iconName,
                colorHex: record.colorHex,
                deviceID: deviceID
            )
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            model.id = record.id
            model.checklistItemID = record.checklistItemID
            model.iconName = record.iconName
            model.colorHex = record.colorHex
            model.suggestionTitleSnapshot = record.suggestionTitleSnapshot
            model.suggestionModelID = record.suggestionModelID
            model.suggestionGeneratedAt = record.suggestionGeneratedAt
            model.userEditedAt = record.userEditedAt
            model.createdAt = record.createdAt
            model.updatedAt = max(record.updatedAt, now)
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            model.clientMutationID = UUID()
        }
    }
}
