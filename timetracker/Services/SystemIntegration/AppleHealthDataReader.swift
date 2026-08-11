import Foundation

nonisolated enum AppleHealthAuthorizationRequestStatus: Equatable, Sendable {
    case unknown
    case shouldRequest
    case unnecessary
}

@MainActor
protocol AppleHealthDataReading: AnyObject {
    var isHealthDataAvailable: Bool { get }

    /// Indicates whether requesting the current read types would present the
    /// system authorization sheet. This does not reveal any read decision.
    func authorizationRequestStatus() async throws
        -> AppleHealthAuthorizationRequestStatus

    /// A successful return means the system processed the request. HealthKit
    /// intentionally does not reveal whether read permission was granted.
    func requestReadAuthorization() async throws

    func samples(overlapping interval: DateInterval) async throws -> AppleHealthSampleBatch
}

@MainActor
protocol AppleHealthReplicaChangeObserving: AnyObject {
    func startObservingReplicaChanges(
        _ handler: @escaping @MainActor @Sendable () async -> Void
    ) async throws
    func stopObservingReplicaChanges()
}

@MainActor
final class UnavailableAppleHealthDataReader: AppleHealthDataReading {
    let isHealthDataAvailable = false

    func authorizationRequestStatus() async throws
        -> AppleHealthAuthorizationRequestStatus
    {
        throw AppleHealthReadError.unavailable
    }

    func requestReadAuthorization() async throws {
        throw AppleHealthReadError.unavailable
    }

    func samples(overlapping interval: DateInterval) async throws -> AppleHealthSampleBatch {
        _ = interval
        throw AppleHealthReadError.unavailable
    }
}

@MainActor
enum AppleHealthDataReaderFactory {
    private static let sharedPlatformReader: any AppleHealthDataReading = {
        #if os(iOS) && canImport(HealthKit)
        return HealthKitAppleHealthDataReader()
        #else
        return UnavailableAppleHealthDataReader()
        #endif
    }()

    static func platformDefault() -> any AppleHealthDataReading {
        sharedPlatformReader
    }
}

#if os(iOS) && canImport(HealthKit)
import HealthKit

private enum AppleHealthReplicaObservationError: Error {
    case backgroundDeliveryUnavailable
}

@MainActor
final class HealthKitAppleHealthDataReader:
    AppleHealthDataReading,
    AppleHealthReplicaChangeReading,
    AppleHealthReplicaChangeObserving
{
    private static let replicaQueryPageLimit = 1000
    private let healthStore: HKHealthStore
    private var replicaObserverQueries: [HKObserverQuery] = []
    private var replicaObservationHandler:
        (@MainActor @Sendable () async -> Void)?

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func authorizationRequestStatus() async throws
        -> AppleHealthAuthorizationRequestStatus
    {
        guard isHealthDataAvailable else {
            throw AppleHealthReadError.unavailable
        }
        try Task.checkCancellation()
        let status = try await healthStore.statusForAuthorizationRequest(
            toShare: [],
            read: readTypes()
        )
        try Task.checkCancellation()
        return Self.authorizationRequestStatus(for: status)
    }

    func requestReadAuthorization() async throws {
        guard isHealthDataAvailable else {
            throw AppleHealthReadError.unavailable
        }
        try Task.checkCancellation()
        let types = try readTypes()
        try await healthStore.requestAuthorization(toShare: [], read: types)
        try Task.checkCancellation()
    }

    func samples(overlapping interval: DateInterval) async throws -> AppleHealthSampleBatch {
        guard isHealthDataAvailable else {
            throw AppleHealthReadError.unavailable
        }
        guard interval.duration > 0 else { return .empty }
        try Task.checkCancellation()

        let predicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: []
        )
        let workouts = try await workoutSamples(predicate: predicate)
        try Task.checkCancellation()
        let sleep = try await sleepSamples(predicate: predicate)
        try Task.checkCancellation()
        return AppleHealthSampleBatch(workouts: workouts, sleep: sleep)
    }

    func replicaChanges(
        after anchors: AppleHealthReplicaAnchors
    ) async throws -> AppleHealthReplicaChangeBatch {
        guard isHealthDataAvailable else {
            throw AppleHealthReadError.unavailable
        }
        try Task.checkCancellation()
        let workoutChanges = try await workoutReplicaChanges(
            after: anchors.workout
        )
        try Task.checkCancellation()
        let sleepChanges = try await sleepReplicaChanges(
            after: anchors.sleep
        )
        try Task.checkCancellation()
        return AppleHealthReplicaChangeBatch(
            workouts: workoutChanges.added,
            deletedWorkoutIDs: workoutChanges.deleted,
            workoutAnchor: workoutChanges.anchor,
            sleep: sleepChanges.added,
            deletedSleepIDs: sleepChanges.deleted,
            sleepAnchor: sleepChanges.anchor
        )
    }

    func startObservingReplicaChanges(
        _ handler: @escaping @MainActor @Sendable () async -> Void
    ) async throws {
        guard isHealthDataAvailable else {
            throw AppleHealthReadError.unavailable
        }
        replicaObservationHandler = handler
        guard replicaObserverQueries.isEmpty else { return }

        let types = try observedSampleTypes()
        let queries = types.map { type in
            HKObserverQuery(
                sampleType: type,
                predicate: nil
            ) { [weak self] _, completion, error in
                guard error == nil else {
                    completion()
                    return
                }
                Task { @MainActor [weak self] in
                    guard let handler =
                        self?.replicaObservationHandler
                    else {
                        completion()
                        return
                    }
                    await handler()
                    completion()
                }
            }
        }
        replicaObserverQueries = queries
        queries.forEach(healthStore.execute)

        do {
            for type in types {
                try await enableBackgroundDelivery(for: type)
            }
        } catch {
            stopObservingReplicaChanges()
            throw error
        }
    }

    func stopObservingReplicaChanges() {
        replicaObserverQueries.forEach(healthStore.stop)
        replicaObserverQueries = []
        replicaObservationHandler = nil
    }

    private func readTypes() throws -> Set<HKObjectType> {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw AppleHealthReadError.requiredTypesUnavailable
        }
        return [HKObjectType.workoutType(), sleepType]
    }

    private func observedSampleTypes() throws -> [HKSampleType] {
        guard let sleepType = HKObjectType.categoryType(
            forIdentifier: .sleepAnalysis
        ) else {
            throw AppleHealthReadError.requiredTypesUnavailable
        }
        return [HKObjectType.workoutType(), sleepType]
    }

    private func enableBackgroundDelivery(
        for type: HKObjectType
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            healthStore.enableBackgroundDelivery(
                for: type,
                frequency: .immediate
            ) { succeeded, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if succeeded {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing:
                        AppleHealthReplicaObservationError
                            .backgroundDeliveryUnavailable
                    )
                }
            }
        }
    }

    private func workoutSamples(predicate: NSPredicate) async throws -> [AppleHealthWorkoutSample] {
        let descriptor = HKSampleQueryDescriptor<HKWorkout>(
            predicates: [.workout(predicate)],
            sortDescriptors: []
        )
        return try await descriptor.result(for: healthStore)
            .map { workout in
                AppleHealthWorkoutSample(
                    id: workout.uuid,
                    kind: Self.workoutKind(for: workout.workoutActivityType),
                    startedAt: workout.startDate,
                    endedAt: workout.endDate,
                    sourceBundleIdentifier: workout.sourceRevision.source.bundleIdentifier
                )
            }
    }

    private func sleepSamples(predicate: NSPredicate) async throws -> [AppleHealthSleepSample] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw AppleHealthReadError.requiredTypesUnavailable
        }
        let descriptor = HKSampleQueryDescriptor<HKCategorySample>(
            predicates: [.categorySample(type: sleepType, predicate: predicate)],
            sortDescriptors: []
        )
        return try await descriptor.result(for: healthStore)
            .compactMap { sample in
                guard let stage = Self.sleepStage(for: sample.value) else { return nil }
                return AppleHealthSleepSample(
                    id: sample.uuid,
                    stage: stage,
                    startedAt: sample.startDate,
                    endedAt: sample.endDate,
                    sourceBundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
                    sourceProductType: sample.sourceRevision.productType
                )
            }
    }

    private func workoutReplicaChanges(
        after anchorData: Data?
    ) async throws -> (
        added: [AppleHealthWorkoutSample],
        deleted: Set<UUID>,
        anchor: Data
    ) {
        var anchor = try Self.decodeReplicaAnchor(anchorData)
        var added: [AppleHealthWorkoutSample] = []
        var deleted: Set<UUID> = []
        while true {
            try Task.checkCancellation()
            let descriptor = HKAnchoredObjectQueryDescriptor<HKWorkout>(
                predicates: [.workout()],
                anchor: anchor,
                limit: Self.replicaQueryPageLimit
            )
            let result = try await descriptor.result(for: healthStore)
            try Task.checkCancellation()
            added.append(contentsOf: result.addedSamples.map { workout in
                AppleHealthWorkoutSample(
                    id: workout.uuid,
                    kind: Self.workoutKind(
                        for: workout.workoutActivityType
                    ),
                    startedAt: workout.startDate,
                    endedAt: workout.endDate,
                    sourceBundleIdentifier:
                    workout.sourceRevision.source.bundleIdentifier
                )
            })
            deleted.formUnion(result.deletedObjects.map(\.uuid))
            anchor = result.newAnchor
            let pageCount = result.addedSamples.count +
                result.deletedObjects.count
            guard pageCount >= Self.replicaQueryPageLimit else {
                return try (
                    added,
                    deleted,
                    Self.encodeReplicaAnchor(result.newAnchor)
                )
            }
        }
    }

    private func sleepReplicaChanges(
        after anchorData: Data?
    ) async throws -> (
        added: [AppleHealthSleepSample],
        deleted: Set<UUID>,
        anchor: Data
    ) {
        guard let sleepType = HKObjectType.categoryType(
            forIdentifier: .sleepAnalysis
        ) else {
            throw AppleHealthReadError.requiredTypesUnavailable
        }
        var anchor = try Self.decodeReplicaAnchor(anchorData)
        var added: [AppleHealthSleepSample] = []
        var deleted: Set<UUID> = []
        while true {
            try Task.checkCancellation()
            let descriptor =
                HKAnchoredObjectQueryDescriptor<HKCategorySample>(
                    predicates: [
                        .categorySample(type: sleepType),
                    ],
                    anchor: anchor,
                    limit: Self.replicaQueryPageLimit
                )
            let result = try await descriptor.result(for: healthStore)
            try Task.checkCancellation()
            added.append(contentsOf: result.addedSamples.compactMap {
                sample in
                guard let stage = Self.sleepStage(
                    for: sample.value
                ) else {
                    return nil
                }
                return AppleHealthSleepSample(
                    id: sample.uuid,
                    stage: stage,
                    startedAt: sample.startDate,
                    endedAt: sample.endDate,
                    sourceBundleIdentifier:
                    sample.sourceRevision.source.bundleIdentifier,
                    sourceProductType:
                    sample.sourceRevision.productType
                )
            })
            deleted.formUnion(result.deletedObjects.map(\.uuid))
            anchor = result.newAnchor
            let pageCount = result.addedSamples.count +
                result.deletedObjects.count
            guard pageCount >= Self.replicaQueryPageLimit else {
                return try (
                    added,
                    deleted,
                    Self.encodeReplicaAnchor(result.newAnchor)
                )
            }
        }
    }

    private static func encodeReplicaAnchor(
        _ anchor: HKQueryAnchor
    ) throws -> Data {
        try NSKeyedArchiver.archivedData(
            withRootObject: anchor,
            requiringSecureCoding: true
        )
    }

    private static func decodeReplicaAnchor(
        _ data: Data?
    ) throws -> HKQueryAnchor? {
        guard let data else { return nil }
        guard let anchor = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: HKQueryAnchor.self,
            from: data
        ) else {
            throw AppleHealthReadError.replicaAnchorUnreadable
        }
        return anchor
    }

    static func workoutKind(for activity: HKWorkoutActivityType) -> AppleHealthWorkoutKind {
        switch activity {
        case .walking:
            .walking
        case .running:
            .running
        case .cycling:
            .cycling
        case .swimming:
            .swimming
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            .strengthTraining
        case .highIntensityIntervalTraining:
            .highIntensityIntervalTraining
        case .yoga:
            .yoga
        case .hiking:
            .hiking
        case .rowing:
            .rowing
        case .dance, .socialDance, .cardioDance:
            .dance
        default:
            .other
        }
    }

    static func sleepStage(for rawValue: Int) -> AppleHealthSleepStage? {
        switch rawValue {
        case HKCategoryValueSleepAnalysis.inBed.rawValue:
            .inBed
        case HKCategoryValueSleepAnalysis.awake.rawValue:
            .awake
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
            .asleepUnspecified
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
            .asleepCore
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
            .asleepDeep
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            .asleepREM
        default:
            nil
        }
    }

    static func authorizationRequestStatus(
        for status: HKAuthorizationRequestStatus
    ) -> AppleHealthAuthorizationRequestStatus {
        switch status {
        case .unknown:
            .unknown
        case .shouldRequest:
            .shouldRequest
        case .unnecessary:
            .unnecessary
        @unknown default:
            .unknown
        }
    }
}
#endif
