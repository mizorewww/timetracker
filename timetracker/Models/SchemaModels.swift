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

enum TimeTrackerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [TimeTrackerSchemaV1.self, TimeTrackerSchemaV2.self, TimeTrackerSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: TimeTrackerSchemaV1.self, toVersion: TimeTrackerSchemaV2.self),
            .lightweight(fromVersion: TimeTrackerSchemaV2.self, toVersion: TimeTrackerSchemaV3.self)
        ]
    }
}

enum TimeTrackerModelRegistry {
    static var currentSchema: Schema {
        Schema(versionedSchema: TimeTrackerSchemaV3.self)
    }

    static var currentModels: [any PersistentModel.Type] {
        TimeTrackerSchemaV3.models
    }

    static var cloudSyncedUserModelNames: Set<String> {
        Set(currentModels.map { String(describing: $0) })
    }
}
