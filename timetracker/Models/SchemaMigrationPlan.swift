import Foundation
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
            TimeTrackerSchemaV8.self
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
                    LegacyTaskCategoryMigrationBuffer.pendingAssignments = tasks.compactMap { task in
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
                    }
                },
                didMigrate: { context in
                    let tasks = Set(try context.fetch(FetchDescriptor<TaskNode>()).map(\.id))
                    let categories = Set(try context.fetch(FetchDescriptor<TaskCategory>()).map(\.id))
                    for assignment in LegacyTaskCategoryMigrationBuffer.pendingAssignments
                    where tasks.contains(assignment.taskID) && categories.contains(assignment.categoryID) {
                        context.insert(TaskCategoryAssignment(
                            taskID: assignment.taskID,
                            categoryID: assignment.categoryID,
                            deviceID: assignment.deviceID
                        ))
                    }
                    LegacyTaskCategoryMigrationBuffer.pendingAssignments = []
                    try context.save()
                }
            ),
            .lightweight(fromVersion: TimeTrackerSchemaV5.self, toVersion: TimeTrackerSchemaV6.self),
            .lightweight(fromVersion: TimeTrackerSchemaV6.self, toVersion: TimeTrackerSchemaV7.self),
            .lightweight(fromVersion: TimeTrackerSchemaV7.self, toVersion: TimeTrackerSchemaV8.self)
        ]
    }
}

private struct LegacyTaskCategoryAssignment {
    let taskID: UUID
    let categoryID: UUID
    let deviceID: String
}

private enum LegacyTaskCategoryMigrationBuffer {
    nonisolated(unsafe) static var pendingAssignments: [LegacyTaskCategoryAssignment] = []
}
