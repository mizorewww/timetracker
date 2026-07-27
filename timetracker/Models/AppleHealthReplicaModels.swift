import Foundation

nonisolated enum AppleHealthReplicaStream: String, CaseIterable, Sendable {
    case workout
    case sleep
}

nonisolated struct AppleHealthReplicaAnchors: Equatable, Sendable {
    let workout: Data?
    let sleep: Data?

    static let empty = AppleHealthReplicaAnchors(
        workout: nil,
        sleep: nil
    )
}

nonisolated struct AppleHealthReplicaChangeBatch: Equatable, Sendable {
    let workouts: [AppleHealthWorkoutSample]
    let deletedWorkoutIDs: Set<UUID>
    let workoutAnchor: Data
    let sleep: [AppleHealthSleepSample]
    let deletedSleepIDs: Set<UUID>
    let sleepAnchor: Data
}

nonisolated struct AppleHealthReplicaSnapshot: Equatable, Sendable {
    let samples: AppleHealthSampleBatch
    let recordCount: Int
    let lastSuccessfulSyncAt: Date?
}

enum AppleHealthReplicaRepositoryError: LocalizedError, Equatable {
    case invalidSample
    case invalidPersistedValue

    var errorDescription: String? {
        switch self {
        case .invalidSample:
            "Apple Health returned a record that could not be stored safely."
        case .invalidPersistedValue:
            "The local Apple Health replica contains an unreadable record."
        }
    }
}
