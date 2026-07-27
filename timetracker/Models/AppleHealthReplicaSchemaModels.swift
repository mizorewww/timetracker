import Foundation
import SwiftData

enum AppleHealthReplicaSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            WorkoutRecord.self,
            SleepRecord.self,
            SyncCheckpoint.self,
        ]
    }

    @Model
    final class WorkoutRecord {
        @Attribute(.unique) var sampleID: UUID = UUID()
        var kindRaw: String = AppleHealthWorkoutKind.other.rawValue
        var startedAt: Date = Date()
        var endedAt: Date = Date()
        var sourceBundleIdentifier: String = ""

        init(
            sampleID: UUID,
            kindRaw: String,
            startedAt: Date,
            endedAt: Date,
            sourceBundleIdentifier: String
        ) {
            self.sampleID = sampleID
            self.kindRaw = kindRaw
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.sourceBundleIdentifier = sourceBundleIdentifier
        }
    }

    @Model
    final class SleepRecord {
        @Attribute(.unique) var sampleID: UUID = UUID()
        var stageRaw: String = AppleHealthSleepStage.asleepUnspecified.rawValue
        var startedAt: Date = Date()
        var endedAt: Date = Date()
        var sourceBundleIdentifier: String = ""
        var sourceProductType: String?

        init(
            sampleID: UUID,
            stageRaw: String,
            startedAt: Date,
            endedAt: Date,
            sourceBundleIdentifier: String,
            sourceProductType: String?
        ) {
            self.sampleID = sampleID
            self.stageRaw = stageRaw
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.sourceBundleIdentifier = sourceBundleIdentifier
            self.sourceProductType = sourceProductType
        }
    }

    @Model
    final class SyncCheckpoint {
        @Attribute(.unique) var streamRaw: String = ""
        var anchorData: Data?
        var lastSuccessfulSyncAt: Date?

        init(
            streamRaw: String,
            anchorData: Data?,
            lastSuccessfulSyncAt: Date?
        ) {
            self.streamRaw = streamRaw
            self.anchorData = anchorData
            self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        }
    }
}

enum AppleHealthReplicaModelRegistry {
    static var currentSchema: Schema {
        Schema(versionedSchema: AppleHealthReplicaSchemaV1.self)
    }
}

enum AppleHealthReplicaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AppleHealthReplicaSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
