import Foundation
import SwiftData

extension SyncDataSnapshot {
    func restoreTasks(context: ModelContext, now: Date, deviceID: String) throws {
        var existing = try context.fetch(FetchDescriptor<TaskNode>())
            .latestByIDMarkingDuplicatesDeleted(now: now, deviceID: deviceID)
        let snapshotIDs = Set(tasks.map(\.id))
        for task in existing.values where !snapshotIDs.contains(task.id) {
            task.deletedAt = now
            task.updatedAt = now
            task.deviceID = deviceID
            task.clientMutationID = UUID()
        }
        for record in tasks {
            let model = existing[record.id] ?? TaskNode(
                title: record.title,
                parentID: record.parentID,
                deviceID: deviceID
            )
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            model.id = record.id
            model.title = record.title
            model.kindRaw = record.kindRaw
            model.parentID = record.parentID
            model.sortOrder = record.sortOrder
            model.path = TaskHierarchyMetadata.canonicalPath(for: record.id)
            model.depth = record.depth
            model.statusRaw = record.statusRaw
            model.colorHex = record.colorHex
            model.iconName = record.iconName
            model.estimatedSeconds = TaskEstimatePolicy.normalized(seconds: record.estimatedSeconds)
            model.dueAt = record.dueAt
            model.notes = record.notes
            model.createdAt = record.createdAt
            model.updatedAt = max(record.updatedAt, now)
            model.archivedAt = record.archivedAt
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            model.clientMutationID = UUID()
        }

        let visibleTasks = existing.values.filter { $0.deletedAt == nil }
        let metadata = TaskHierarchyMetadataService().normalizedMetadata(tasks: visibleTasks)
        for model in visibleTasks {
            guard let normalized = metadata[model.id] else { continue }
            model.parentID = normalized.parentID
            model.depth = normalized.depth
            model.path = normalized.path
        }
    }

    func restoreTaskCategories(context: ModelContext, now: Date, deviceID: String) throws {
        var existing = try context.fetch(FetchDescriptor<TaskCategory>())
            .latestByIDMarkingDuplicatesDeleted(now: now, deviceID: deviceID)
        let snapshotIDs = Set(taskCategories.map(\.id))
        for category in existing.values where !snapshotIDs.contains(category.id) {
            category.deletedAt = now
            category.updatedAt = now
            category.deviceID = deviceID
            category.clientMutationID = UUID()
        }
        for record in taskCategories {
            let model = existing[record.id] ?? TaskCategory(
                title: record.title,
                deviceID: deviceID
            )
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            model.id = record.id
            model.title = record.title
            model.colorHex = record.colorHex
            model.iconName = record.iconName
            model.includesInForecast = record.includesInForecast
            model.sortOrder = record.sortOrder
            model.createdAt = record.createdAt
            model.updatedAt = max(record.updatedAt, now)
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            model.clientMutationID = UUID()
        }
    }

    func restoreTaskCategoryAssignments(
        context: ModelContext,
        now: Date,
        deviceID: String
    ) throws {
        var existing = try context.fetch(FetchDescriptor<TaskCategoryAssignment>())
            .latestByIDMarkingDuplicatesDeleted(now: now, deviceID: deviceID)
        let snapshotIDs = Set(taskCategoryAssignments.map(\.id))
        for assignment in existing.values where !snapshotIDs.contains(assignment.id) {
            assignment.deletedAt = now
            assignment.updatedAt = now
            assignment.deviceID = deviceID
            assignment.clientMutationID = UUID()
        }
        for record in taskCategoryAssignments {
            let model = existing[record.id] ?? TaskCategoryAssignment(
                taskID: record.taskID,
                categoryID: record.categoryID,
                deviceID: deviceID
            )
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            model.id = record.id
            model.taskID = record.taskID
            model.categoryID = record.categoryID
            model.createdAt = record.createdAt
            model.updatedAt = max(record.updatedAt, now)
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            model.clientMutationID = UUID()
        }
    }
}
