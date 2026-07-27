import Foundation
import SwiftData
@testable import timetracker

@MainActor
func makeAppleHealthReplicaTestRepository()
    throws -> SwiftDataAppleHealthReplicaRepository
{
    let container = try AppleHealthReplicaModelContainerFactory
        .makeInMemoryContainer(
            name: "AppleHealthReplicaTests-\(UUID().uuidString)"
        )
    return SwiftDataAppleHealthReplicaRepository(container: container)
}

func appleHealthWorkout(
    id: UUID,
    kind: AppleHealthWorkoutKind = .walking,
    start: TimeInterval,
    end: TimeInterval,
    source: String = "test.health"
) -> AppleHealthWorkoutSample {
    AppleHealthWorkoutSample(
        id: id,
        kind: kind,
        startedAt: Date(timeIntervalSince1970: start),
        endedAt: Date(timeIntervalSince1970: end),
        sourceBundleIdentifier: source
    )
}

func appleHealthSleep(
    id: UUID,
    stage: AppleHealthSleepStage = .asleepCore,
    start: TimeInterval,
    end: TimeInterval,
    source: String = "test.health",
    productType: String? = "Watch-Test"
) -> AppleHealthSleepSample {
    AppleHealthSleepSample(
        id: id,
        stage: stage,
        startedAt: Date(timeIntervalSince1970: start),
        endedAt: Date(timeIntervalSince1970: end),
        sourceBundleIdentifier: source,
        sourceProductType: productType
    )
}
