import Foundation
import SwiftData

enum TimeTrackerSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskNode.self,
            TimeSession.self,
            TimeSegment.self,
            PomodoroRun.self,
            DailySummary.self
        ]
    }
}

enum TimeTrackerSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 1, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskNode.self,
            TimeSession.self,
            TimeSegment.self,
            PomodoroRun.self,
            DailySummary.self,
            CountdownEvent.self
        ]
    }
}

enum TimeTrackerSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 2, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskNode.self,
            TimeSession.self,
            TimeSegment.self,
            PomodoroRun.self,
            DailySummary.self,
            CountdownEvent.self,
            SyncedPreference.self,
            ChecklistItem.self
        ]
    }
}

enum TimeTrackerSchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 3, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskNode.self,
            TaskCategory.self,
            TimeSession.self,
            TimeSegment.self,
            PomodoroRun.self,
            DailySummary.self,
            CountdownEvent.self,
            SyncedPreference.self,
            ChecklistItem.self
        ]
    }

    @Model
    final class TaskNode {
        var id: UUID = UUID()
        var title: String = ""
        var kindRaw: String = "task"
        var parentID: UUID?
        var categoryID: UUID?
        var sortOrder: Double = 0
        var path: String = ""
        var depth: Int = 0
        var statusRaw: String = TaskStatus.active.rawValue
        var colorHex: String?
        var iconName: String?
        var estimatedSeconds: Int?
        var dueAt: Date?
        var notes: String?
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var archivedAt: Date?
        var deletedAt: Date?
        var deviceID: String = ""
        var clientMutationID: UUID = UUID()

        init(
            title: String,
            parentID: UUID?,
            deviceID: String,
            categoryID: UUID? = nil,
            colorHex: String? = nil,
            iconName: String? = nil,
            sortOrder: Double = 0
        ) {
            self.id = UUID()
            self.title = title
            self.parentID = parentID
            self.categoryID = categoryID
            self.sortOrder = sortOrder
            self.path = ""
            self.depth = 0
            self.statusRaw = TaskStatus.active.rawValue
            self.colorHex = colorHex
            self.iconName = iconName
            self.createdAt = Date()
            self.updatedAt = Date()
            self.deviceID = deviceID
            self.clientMutationID = UUID()
        }
    }

    @Model
    final class TaskCategory {
        var id: UUID = UUID()
        var title: String = ""
        var colorHex: String?
        var iconName: String?
        var includesInForecast: Bool = true
        var sortOrder: Double = 0
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?
        var deviceID: String = ""
        var clientMutationID: UUID = UUID()

        init(
            title: String,
            deviceID: String,
            colorHex: String? = nil,
            iconName: String? = nil,
            includesInForecast: Bool = true,
            sortOrder: Double = 0
        ) {
            self.id = UUID()
            self.title = title
            self.colorHex = colorHex
            self.iconName = iconName
            self.includesInForecast = includesInForecast
            self.sortOrder = sortOrder
            self.createdAt = Date()
            self.updatedAt = Date()
            self.deviceID = deviceID
            self.clientMutationID = UUID()
        }
    }
}

enum TimeTrackerSchemaV5: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 4, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskNode.self,
            TaskCategory.self,
            TaskCategoryAssignment.self,
            TimeSession.self,
            TimeSegment.self,
            PomodoroRun.self,
            DailySummary.self,
            CountdownEvent.self,
            SyncedPreference.self,
            ChecklistItem.self
        ]
    }
}

enum TimeTrackerSchemaV6: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 5, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskNode.self,
            TaskCategory.self,
            TaskCategoryAssignment.self,
            InboxItem.self,
            TimeSession.self,
            TimeSegment.self,
            PomodoroRun.self,
            DailySummary.self,
            CountdownEvent.self,
            SyncedPreference.self,
            ChecklistItem.self
        ]
    }
}

enum TimeTrackerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            TimeTrackerSchemaV1.self,
            TimeTrackerSchemaV2.self,
            TimeTrackerSchemaV3.self,
            TimeTrackerSchemaV4.self,
            TimeTrackerSchemaV5.self,
            TimeTrackerSchemaV6.self
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
            .lightweight(fromVersion: TimeTrackerSchemaV5.self, toVersion: TimeTrackerSchemaV6.self)
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

enum TimeTrackerModelRegistry {
    static var currentSchema: Schema {
        Schema(versionedSchema: TimeTrackerSchemaV6.self)
    }

    static var currentModels: [any PersistentModel.Type] {
        TimeTrackerSchemaV6.models
    }

    static var cloudSyncedUserModelNames: Set<String> {
        Set(currentModels.map { String(describing: $0) })
    }
}
