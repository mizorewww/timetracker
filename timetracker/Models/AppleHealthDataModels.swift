import Foundation

nonisolated enum AppleHealthWorkoutKind: String, CaseIterable, Hashable, Sendable {
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
        self.workouts = workouts.sorted(by: Self.workoutChronology)
        self.sleep = sleep.sorted(by: Self.sleepChronology)
    }

    static let empty = AppleHealthSampleBatch(workouts: [], sleep: [])

    static func workoutChronology(
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

    static func sleepChronology(
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

nonisolated struct AppleHealthTimelineItem: Identifiable, Equatable, Sendable {
    let id: TimelineEntryID
    let subject: TimelineEntrySubject
    let interval: DateInterval

    var titleLocalizationKey: String {
        switch subject {
        case .task:
            "health.timeline.workout.other"
        case .appleHealthWorkout:
            taskRole.map(AppleHealthTaskCatalog.taskDefinition)?
                .titleLocalizationKey ?? "health.timeline.workout.other"
        case .appleHealthSleep:
            "health.timeline.sleep"
        }
    }

    var categoryLocalizationKey: String {
        guard let taskRole else {
            return "health.timeline.exerciseCategory"
        }
        return AppleHealthTaskCatalog.categoryDefinition(
            for: taskRole.categoryRole
        ).titleLocalizationKey
    }

    var iconName: String {
        taskRole.map(AppleHealthTaskCatalog.taskDefinition)?
            .iconName ?? "figure.mixed.cardio"
    }

    var colorHex: String {
        taskRole.map(AppleHealthTaskCatalog.taskDefinition)?
            .colorHex ?? "FF3B30"
    }
}

nonisolated enum AppleHealthTimelineState: Equatable, Sendable {
    case disabled
    case unavailable
    case ready
    case requesting
    case loading(DateInterval)
    case content(interval: DateInterval, refreshedAt: Date, itemCount: Int)
    case noReadableData(interval: DateInterval, refreshedAt: Date)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .requesting, .loading:
            true
        case .disabled, .unavailable, .ready, .content, .noReadableData, .failed:
            false
        }
    }
}

nonisolated enum AppleHealthReadError: LocalizedError, Equatable, Sendable {
    case unavailable
    case requiredTypesUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            NSLocalizedString("health.error.unavailable", comment: "")
        case .requiredTypesUnavailable:
            NSLocalizedString("health.error.requiredTypesUnavailable", comment: "")
        }
    }
}
