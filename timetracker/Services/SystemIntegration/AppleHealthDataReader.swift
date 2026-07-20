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
final class UnavailableAppleHealthDataReader: AppleHealthDataReading {
    let isHealthDataAvailable = false

    func authorizationRequestStatus() async throws
        -> AppleHealthAuthorizationRequestStatus {
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
    private static let sharedReader: any AppleHealthDataReading = {
        #if DEBUG && os(iOS)
        if let reader = UITestAppleHealthDataReader.makeIfRequested() {
            return reader
        }
        #endif
        #if os(iOS) && canImport(HealthKit)
        return HealthKitAppleHealthDataReader()
        #else
        return UnavailableAppleHealthDataReader()
        #endif
    }()

    static func platformDefault() -> any AppleHealthDataReading {
        sharedReader
    }
}

#if os(iOS) && canImport(HealthKit)
import HealthKit

@MainActor
final class HealthKitAppleHealthDataReader: AppleHealthDataReading {
    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func authorizationRequestStatus() async throws
        -> AppleHealthAuthorizationRequestStatus {
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

    private func readTypes() throws -> Set<HKObjectType> {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw AppleHealthReadError.requiredTypesUnavailable
        }
        return [HKObjectType.workoutType(), sleepType]
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
