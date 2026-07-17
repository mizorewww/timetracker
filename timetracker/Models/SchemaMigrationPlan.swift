import Foundation
import os
import SwiftData

enum TimeTrackerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            TimeTrackerSchemaV1.self,
            TimeTrackerSchemaV2.self,
            TimeTrackerSchemaV3.self,
            TimeTrackerSchemaV4.self,
            TimeTrackerSchemaV5.self,
            TimeTrackerSchemaV6.self,
            TimeTrackerSchemaV7.self,
            TimeTrackerSchemaV8.self,
            TimeTrackerSchemaV9.self,
            TimeTrackerSchemaV10.self,
            TimeTrackerSchemaV11.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: TimeTrackerSchemaV1.self, toVersion: TimeTrackerSchemaV2.self),
            .lightweight(fromVersion: TimeTrackerSchemaV2.self, toVersion: TimeTrackerSchemaV3.self),
            .lightweight(fromVersion: TimeTrackerSchemaV3.self, toVersion: TimeTrackerSchemaV4.self),
            .custom(
                fromVersion: TimeTrackerSchemaV4.self,
                toVersion: TimeTrackerSchemaV5.self,
                willMigrate: { context in
                    let tasks = try context.fetch(FetchDescriptor<TimeTrackerSchemaV4.TaskNode>())
                    LegacyTaskCategoryMigrationBuffer.replace(tasks.compactMap { task in
                        guard task.parentID == nil,
                              task.deletedAt == nil,
                              let categoryID = task.categoryID else {
                            return nil
                        }
                        return LegacyTaskCategoryAssignment(
                            taskID: task.id,
                            categoryID: categoryID,
                            deviceID: task.deviceID
                        )
                    })
                },
                didMigrate: { context in
                    let tasks = Set(try context.fetch(FetchDescriptor<TaskNode>()).map(\.id))
                    let categories = Set(try context.fetch(FetchDescriptor<TaskCategory>()).map(\.id))
                    for assignment in LegacyTaskCategoryMigrationBuffer.consume()
                    where tasks.contains(assignment.taskID) && categories.contains(assignment.categoryID) {
                        context.insert(TaskCategoryAssignment(
                            taskID: assignment.taskID,
                            categoryID: assignment.categoryID,
                            deviceID: assignment.deviceID
                        ))
                    }
                    try context.save()
                }
            ),
            .lightweight(fromVersion: TimeTrackerSchemaV5.self, toVersion: TimeTrackerSchemaV6.self),
            .lightweight(fromVersion: TimeTrackerSchemaV6.self, toVersion: TimeTrackerSchemaV7.self),
            .lightweight(fromVersion: TimeTrackerSchemaV7.self, toVersion: TimeTrackerSchemaV8.self),
            .lightweight(fromVersion: TimeTrackerSchemaV8.self, toVersion: TimeTrackerSchemaV9.self),
            .custom(
                fromVersion: TimeTrackerSchemaV9.self,
                toVersion: TimeTrackerSchemaV10.self,
                willMigrate: nil,
                didMigrate: migrateInboxSuggestionIdentity
            ),
            .lightweight(fromVersion: TimeTrackerSchemaV10.self, toVersion: TimeTrackerSchemaV11.self)
        ]
    }

    private static func migrateInboxSuggestionIdentity(context: ModelContext) throws {
        let items = try context.fetch(FetchDescriptor<InboxItem>())
        let suggestions = try context.fetch(FetchDescriptor<InboxSuggestion>())
        let activeSuggestionItemIDs = Set(
            suggestions.lazy.filter { $0.deletedAt == nil }.map(\.inboxItemID)
        )
        let itemByID = items.reduce(into: [UUID: InboxItem]()) { result, item in
            result[item.id] = item
        }

        for item in items {
            item.materializeSuggestionIdentity()
            if item.suggestionGeneratedAt != nil,
               activeSuggestionItemIDs.contains(item.id) == false {
                item.dismissedSuggestionRevisionID = item.effectiveSuggestionRevisionID
            }
        }
        for suggestion in suggestions {
            let item = itemByID[suggestion.inboxItemID]
            suggestion.inboxItemContextID = item?.effectiveSuggestionContextID ?? suggestion.inboxItemID
            suggestion.inboxItemRevisionID = item?.effectiveSuggestionRevisionID ?? suggestion.inboxItemID
        }
        try context.save()
    }
}

private struct LegacyTaskCategoryAssignment {
    let taskID: UUID
    let categoryID: UUID
    let deviceID: String
}

private enum LegacyTaskCategoryMigrationBuffer {
    private static let storage = OSAllocatedUnfairLock(
        initialState: [LegacyTaskCategoryAssignment]()
    )

    static func replace(_ assignments: [LegacyTaskCategoryAssignment]) {
        storage.withLock { pendingAssignments in
            pendingAssignments = assignments
        }
    }

    static func consume() -> [LegacyTaskCategoryAssignment] {
        storage.withLock { pendingAssignments in
            defer { pendingAssignments.removeAll(keepingCapacity: true) }
            return pendingAssignments
        }
    }
}
