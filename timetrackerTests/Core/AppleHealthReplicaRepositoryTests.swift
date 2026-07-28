import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct AppleHealthReplicaRepositoryTests {
    @Test @MainActor
    func replicaSchemaAndStoreStayOutsideTheCloudSyncedModelContainer() {
        let healthSchema = AppleHealthReplicaModelRegistry.currentSchema

        #expect(
            healthSchema.entity(
                for: AppleHealthReplicaSchemaV1.WorkoutRecord.self
            ) != nil
        )
        #expect(
            healthSchema.entity(
                for: AppleHealthReplicaSchemaV1.SleepRecord.self
            ) != nil
        )
        #expect(
            TimeTrackerModelRegistry.currentSchema.entity(
                for: AppleHealthReplicaSchemaV1.WorkoutRecord.self
            ) == nil
        )
        #expect(
            TimeTrackerModelRegistry.cloudSyncedUserModelNames
                .contains("WorkoutRecord") == false
        )
        #expect(
            AppleHealthReplicaModelContainerFactory.persistentStoreURL
                != AppCloudSync.persistentStoreURL
        )
        #expect(
            AppleHealthReplicaMigrationPlan.schemas.last?.versionIdentifier
                == AppleHealthReplicaSchemaV1.versionIdentifier
        )
    }

    @Test @MainActor
    func applyIsDeterministicIdempotentAndAdvancesBothAnchors() throws {
        let repository = try makeAppleHealthReplicaTestRepository()
        let workoutID = UUID()
        let sleepID = UUID()
        let firstSyncAt = Date(timeIntervalSince1970: 500)
        let firstChanges = AppleHealthReplicaChangeBatch(
            workouts: [
                appleHealthWorkout(
                    id: workoutID,
                    kind: .walking,
                    start: 100,
                    end: 200
                ),
            ],
            deletedWorkoutIDs: [],
            workoutAnchor: Data("workout-1".utf8),
            sleep: [
                appleHealthSleep(
                    id: sleepID,
                    stage: .asleepCore,
                    start: 250,
                    end: 400
                ),
            ],
            deletedSleepIDs: [],
            sleepAnchor: Data("sleep-1".utf8)
        )

        try repository.apply(firstChanges, syncedAt: firstSyncAt)
        try repository.apply(firstChanges, syncedAt: firstSyncAt)

        let snapshot = try repository.snapshot(
            overlapping: DateInterval(
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: 1000)
            )
        )
        #expect(snapshot.samples.workouts.count == 1)
        #expect(snapshot.samples.sleep.count == 1)
        #expect(snapshot.lastSuccessfulSyncAt == firstSyncAt)
        #expect(try repository.anchors() == AppleHealthReplicaAnchors(
            workout: Data("workout-1".utf8),
            sleep: Data("sleep-1".utf8)
        ))
    }

    @Test @MainActor
    func applyPreservesHealthKitPointSamplesAndAdvancesBothAnchors() throws {
        let repository = try makeAppleHealthReplicaTestRepository()
        let workout = appleHealthWorkout(
            id: UUID(),
            start: 100,
            end: 100
        )
        let sleep = appleHealthSleep(
            id: UUID(),
            start: 200,
            end: 200
        )
        let syncedAt = Date(timeIntervalSince1970: 500)

        try repository.apply(
            AppleHealthReplicaChangeBatch(
                workouts: [workout],
                deletedWorkoutIDs: [],
                workoutAnchor: Data("workout-point".utf8),
                sleep: [sleep],
                deletedSleepIDs: [],
                sleepAnchor: Data("sleep-point".utf8)
            ),
            syncedAt: syncedAt
        )

        let snapshot = try repository.allSamples()
        #expect(snapshot.samples.workouts == [workout])
        #expect(snapshot.samples.sleep == [sleep])
        #expect(snapshot.recordCount == 2)
        #expect(snapshot.lastSuccessfulSyncAt == syncedAt)
        #expect(try repository.anchors() == AppleHealthReplicaAnchors(
            workout: Data("workout-point".utf8),
            sleep: Data("sleep-point".utf8)
        ))
    }

    @Test @MainActor
    func reverseIntervalRejectsTheWholeBatchWithoutAdvancingAnchors() throws {
        let repository = try makeAppleHealthReplicaTestRepository()
        let original = AppleHealthReplicaChangeBatch(
            workouts: [
                appleHealthWorkout(
                    id: UUID(),
                    start: 100,
                    end: 200
                ),
            ],
            deletedWorkoutIDs: [],
            workoutAnchor: Data("workout-1".utf8),
            sleep: [],
            deletedSleepIDs: [],
            sleepAnchor: Data("sleep-1".utf8)
        )
        try repository.apply(
            original,
            syncedAt: Date(timeIntervalSince1970: 300)
        )

        #expect(throws: AppleHealthReplicaRepositoryError.invalidSample) {
            try repository.apply(
                AppleHealthReplicaChangeBatch(
                    workouts: [
                        appleHealthWorkout(
                            id: UUID(),
                            start: 500,
                            end: 400
                        ),
                    ],
                    deletedWorkoutIDs: [],
                    workoutAnchor: Data("workout-2".utf8),
                    sleep: [],
                    deletedSleepIDs: [],
                    sleepAnchor: Data("sleep-2".utf8)
                ),
                syncedAt: Date(timeIntervalSince1970: 600)
            )
        }

        #expect(try repository.allSamples().samples.workouts ==
            original.workouts)
        #expect(try repository.allSamples().recordCount == 1)
        #expect(try repository.anchors() == AppleHealthReplicaAnchors(
            workout: Data("workout-1".utf8),
            sleep: Data("sleep-1".utf8)
        ))
    }

    @Test @MainActor
    func applyConvergesHealthKitModificationAndExplicitDeletion() throws {
        let repository = try makeAppleHealthReplicaTestRepository()
        let workoutID = UUID()
        let sleepID = UUID()
        try repository.apply(
            AppleHealthReplicaChangeBatch(
                workouts: [
                    appleHealthWorkout(
                        id: workoutID,
                        kind: .walking,
                        start: 100,
                        end: 200
                    ),
                ],
                deletedWorkoutIDs: [],
                workoutAnchor: Data("workout-1".utf8),
                sleep: [
                    appleHealthSleep(
                        id: sleepID,
                        start: 250,
                        end: 400
                    ),
                ],
                deletedSleepIDs: [],
                sleepAnchor: Data("sleep-1".utf8)
            ),
            syncedAt: Date(timeIntervalSince1970: 500)
        )

        try repository.apply(
            AppleHealthReplicaChangeBatch(
                workouts: [
                    appleHealthWorkout(
                        id: workoutID,
                        kind: .running,
                        start: 110,
                        end: 230
                    ),
                ],
                deletedWorkoutIDs: [],
                workoutAnchor: Data("workout-2".utf8),
                sleep: [],
                deletedSleepIDs: [sleepID],
                sleepAnchor: Data("sleep-2".utf8)
            ),
            syncedAt: Date(timeIntervalSince1970: 600)
        )

        let snapshot = try repository.snapshot(
            overlapping: DateInterval(
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: 1000)
            )
        )
        let workout = try #require(snapshot.samples.workouts.first)
        #expect(snapshot.samples.workouts.count == 1)
        #expect(workout.kind == .running)
        #expect(workout.startedAt == Date(timeIntervalSince1970: 110))
        #expect(workout.endedAt == Date(timeIntervalSince1970: 230))
        #expect(snapshot.samples.sleep.isEmpty)
        #expect(snapshot.lastSuccessfulSyncAt == Date(timeIntervalSince1970: 600))
        #expect(try repository.anchors() == AppleHealthReplicaAnchors(
            workout: Data("workout-2".utf8),
            sleep: Data("sleep-2".utf8)
        ))
    }

    @Test @MainActor
    func rangeSnapshotReturnsImmutableChronologicalValuesOnly() throws {
        let repository = try makeAppleHealthReplicaTestRepository()
        let earlyID = UUID()
        let lateID = UUID()
        try repository.apply(
            AppleHealthReplicaChangeBatch(
                workouts: [
                    appleHealthWorkout(
                        id: lateID,
                        start: 300,
                        end: 400
                    ),
                    appleHealthWorkout(
                        id: earlyID,
                        start: 100,
                        end: 200
                    ),
                ],
                deletedWorkoutIDs: [],
                workoutAnchor: Data(),
                sleep: [],
                deletedSleepIDs: [],
                sleepAnchor: Data()
            ),
            syncedAt: Date(timeIntervalSince1970: 500)
        )

        let snapshot = try repository.snapshot(
            overlapping: DateInterval(
                start: Date(timeIntervalSince1970: 150),
                end: Date(timeIntervalSince1970: 350)
            )
        )

        #expect(snapshot.samples.workouts.map(\.id) == [earlyID, lateID])
        #expect(snapshot.samples.sleep.isEmpty)
        #expect(snapshot.recordCount == 2)
    }

    @Test @MainActor
    func rangeSnapshotDoesNotDecodeUnrelatedRowsOutsideTheInterval() throws {
        let container = try AppleHealthReplicaModelContainerFactory
            .makeInMemoryContainer(
                name: "AppleHealthReplicaRangePredicate-\(UUID().uuidString)"
            )
        let repository = SwiftDataAppleHealthReplicaRepository(
            container: container
        )
        let context = ModelContext(container)
        context.insert(
            AppleHealthReplicaSchemaV1.WorkoutRecord(
                sampleID: UUID(),
                kindRaw: "future-unknown-kind",
                startedAt: Date(timeIntervalSince1970: 10000),
                endedAt: Date(timeIntervalSince1970: 11000),
                sourceBundleIdentifier: "future.health"
            )
        )
        try context.save()

        let snapshot = try repository.snapshot(
            overlapping: DateInterval(
                start: Date(timeIntervalSince1970: 100),
                end: Date(timeIntervalSince1970: 200)
            )
        )

        #expect(snapshot.samples == .empty)
        #expect(snapshot.recordCount == 1)
    }

    @Test @MainActor
    func largeIncrementalBatchConvergesAcrossPredicateChunks() throws {
        let repository = try makeAppleHealthReplicaTestRepository()
        let IDs = (0 ..< 825).map { _ in UUID() }
        let initial = IDs.enumerated().map { index, id in
            appleHealthWorkout(
                id: id,
                kind: .walking,
                start: TimeInterval(index * 10),
                end: TimeInterval(index * 10 + 5)
            )
        }
        try repository.apply(
            AppleHealthReplicaChangeBatch(
                workouts: initial,
                deletedWorkoutIDs: [],
                workoutAnchor: Data("large-1".utf8),
                sleep: [],
                deletedSleepIDs: [],
                sleepAnchor: Data()
            ),
            syncedAt: Date(timeIntervalSince1970: 9000)
        )

        let updated = initial.dropFirst(25).map {
            appleHealthWorkout(
                id: $0.id,
                kind: .running,
                start: $0.startedAt.timeIntervalSince1970,
                end: $0.endedAt.timeIntervalSince1970
            )
        }
        try repository.apply(
            AppleHealthReplicaChangeBatch(
                workouts: updated,
                deletedWorkoutIDs: Set(IDs.prefix(25)),
                workoutAnchor: Data("large-2".utf8),
                sleep: [],
                deletedSleepIDs: [],
                sleepAnchor: Data()
            ),
            syncedAt: Date(timeIntervalSince1970: 10000)
        )

        let snapshot = try repository.allSamples()
        #expect(snapshot.samples.workouts.count == 800)
        #expect(snapshot.samples.workouts.allSatisfy { $0.kind == .running })
        #expect(snapshot.recordCount == 800)
        #expect(try repository.anchors().workout == Data("large-2".utf8))
    }

    @Test @MainActor
    func clearRemovesRecordsAndAnchorsTogether() throws {
        let repository = try makeAppleHealthReplicaTestRepository()
        try repository.apply(
            AppleHealthReplicaChangeBatch(
                workouts: [
                    appleHealthWorkout(
                        id: UUID(),
                        start: 100,
                        end: 200
                    ),
                ],
                deletedWorkoutIDs: [],
                workoutAnchor: Data("workout".utf8),
                sleep: [],
                deletedSleepIDs: [],
                sleepAnchor: Data("sleep".utf8)
            ),
            syncedAt: Date(timeIntervalSince1970: 500)
        )

        try repository.clear()

        #expect(try repository.anchors() == .empty)
        #expect(try repository.allSamples().samples == .empty)
        #expect(try repository.allSamples().recordCount == 0)
        #expect(try repository.allSamples().lastSuccessfulSyncAt == nil)
    }
}
