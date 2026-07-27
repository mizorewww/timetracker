import Foundation

struct TimeTrackerUserDataExport: Codable, Equatable {
    let format: String
    let schemaVersion: Int
    let exportedAt: Date
    let appVersion: String
    let businessData: SyncDataSnapshot
    let appleHealth: AppleHealthReplicaExport

    init(
        exportedAt: Date,
        appVersion: String,
        businessData: SyncDataSnapshot,
        appleHealth: AppleHealthReplicaExport
    ) {
        format = "timetracker.userData"
        schemaVersion = 1
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.businessData = businessData
        self.appleHealth = appleHealth
    }
}

struct AppleHealthReplicaExport: Codable, Equatable {
    struct WorkoutRecord: Codable, Equatable {
        let id: UUID
        let kind: String
        let startedAt: Date
        let endedAt: Date
        let sourceBundleIdentifier: String

        init(_ sample: AppleHealthWorkoutSample) {
            id = sample.id
            kind = sample.kind.rawValue
            startedAt = sample.startedAt
            endedAt = sample.endedAt
            sourceBundleIdentifier = sample.sourceBundleIdentifier
        }
    }

    struct SleepRecord: Codable, Equatable {
        let id: UUID
        let stage: String
        let startedAt: Date
        let endedAt: Date
        let sourceBundleIdentifier: String
        let sourceProductType: String?

        init(_ sample: AppleHealthSleepSample) {
            id = sample.id
            stage = sample.stage.rawValue
            startedAt = sample.startedAt
            endedAt = sample.endedAt
            sourceBundleIdentifier = sample.sourceBundleIdentifier
            sourceProductType = sample.sourceProductType
        }
    }

    let schemaVersion: Int
    let recordCount: Int
    let lastSuccessfulSyncAt: Date?
    let workouts: [WorkoutRecord]
    let sleep: [SleepRecord]

    init(snapshot: AppleHealthReplicaSnapshot) {
        schemaVersion = 1
        recordCount = snapshot.recordCount
        lastSuccessfulSyncAt = snapshot.lastSuccessfulSyncAt
        workouts = snapshot.samples.workouts.map(WorkoutRecord.init)
        sleep = snapshot.samples.sleep.map(SleepRecord.init)
    }
}
