import Foundation
import SwiftData

@MainActor
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
        let logicalWinnerIDs = logicalChecklistItemVisualWinnerIDs()
        let supersededAt = now.addingTimeInterval(-1)
        for visual in existing.values where !snapshotIDs.contains(visual.id) {
            visual.deletedAt = supersededAt
            visual.updatedAt = supersededAt
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
            model.updatedAt = logicalWinnerIDs.contains(record.id)
                ? max(record.updatedAt, now)
                : record.updatedAt
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            model.clientMutationID = record.id
        }
    }

    private func logicalChecklistItemVisualWinnerIDs() -> Set<UUID> {
        var winnersByItemID: [UUID: ChecklistItemVisualRecord] = [:]
        winnersByItemID.reserveCapacity(checklistItemVisuals.count)
        for record in checklistItemVisuals {
            guard let current = winnersByItemID[record.checklistItemID] else {
                winnersByItemID[record.checklistItemID] = record
                continue
            }
            if record.isPreferredLogicalWinner(over: current) {
                winnersByItemID[record.checklistItemID] = record
            }
        }
        return Set(winnersByItemID.values.map(\.id))
    }
}
