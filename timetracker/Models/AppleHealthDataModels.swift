import Foundation

nonisolated enum AppleHealthWorkoutKind: String, CaseIterable, Equatable, Sendable {
    case walking
    case running
    case cycling
    case swimming
    case strengthTraining
    case highIntensityIntervalTraining
    case yoga
    case hiking
    case rowing
    case dance
    case other
}

nonisolated enum AppleHealthSleepStage: String, Equatable, Sendable {
    case inBed
    case awake
    case asleepUnspecified
    case asleepCore
    case asleepDeep
    case asleepREM

    var isAsleep: Bool {
        switch self {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
            true
        case .inBed, .awake:
            false
        }
    }
}

nonisolated struct AppleHealthWorkoutSample: Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: AppleHealthWorkoutKind
    let startedAt: Date
    let endedAt: Date
    let sourceBundleIdentifier: String
}

nonisolated struct AppleHealthSleepSample: Identifiable, Equatable, Sendable {
    let id: UUID
    let stage: AppleHealthSleepStage
    let startedAt: Date
    let endedAt: Date
    let sourceBundleIdentifier: String
}

nonisolated struct AppleHealthSampleBatch: Equatable, Sendable {
    let workouts: [AppleHealthWorkoutSample]
    let sleep: [AppleHealthSleepSample]

    init(
        workouts: [AppleHealthWorkoutSample],
        sleep: [AppleHealthSleepSample]
    ) {
        self.workouts = workouts.sorted(by: Self.workoutPrecedes)
        self.sleep = sleep.sorted(by: Self.sleepPrecedes)
    }

    static let empty = AppleHealthSampleBatch(workouts: [], sleep: [])

    private static func workoutPrecedes(
        _ lhs: AppleHealthWorkoutSample,
        _ rhs: AppleHealthWorkoutSample
    ) -> Bool {
        chronology(
            lhsStart: lhs.startedAt,
            lhsEnd: lhs.endedAt,
            lhsID: lhs.id,
            rhsStart: rhs.startedAt,
            rhsEnd: rhs.endedAt,
            rhsID: rhs.id
        )
    }

    private static func sleepPrecedes(
        _ lhs: AppleHealthSleepSample,
        _ rhs: AppleHealthSleepSample
    ) -> Bool {
        chronology(
            lhsStart: lhs.startedAt,
            lhsEnd: lhs.endedAt,
            lhsID: lhs.id,
            rhsStart: rhs.startedAt,
            rhsEnd: rhs.endedAt,
            rhsID: rhs.id
        )
    }

    private static func chronology(
        lhsStart: Date,
        lhsEnd: Date,
        lhsID: UUID,
        rhsStart: Date,
        rhsEnd: Date,
        rhsID: UUID
    ) -> Bool {
        if lhsStart != rhsStart { return lhsStart < rhsStart }
        if lhsEnd != rhsEnd { return lhsEnd < rhsEnd }
        return lhsID.uuidString < rhsID.uuidString
    }
}

nonisolated enum AppleHealthReadError: LocalizedError, Equatable, Sendable {
    case unavailable
    case requiredTypesUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Apple Health data is unavailable on this device."
        case .requiredTypesUnavailable:
            "Workout or sleep data is unavailable on this device."
        }
    }
}
