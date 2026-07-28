import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct AppleHealthReplicaSyncServiceTests {
    @Test @MainActor
    func firstSyncCommitsRowsThenReusesPersistedAnchors() async throws {
        let repository = try makeAppleHealthReplicaTestRepository()
        let workoutID = UUID()
        let sleepID = UUID()
        let first = AppleHealthReplicaChangeBatch(
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
        )
        let second = AppleHealthReplicaChangeBatch(
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
        )
        let reader = ScriptedAppleHealthReplicaChangeReader(
            results: [.success(first), .success(second)]
        )
        let service = AppleHealthReplicaSyncService(
            reader: reader,
            repository: repository
        )

        _ = try await service.synchronize(
            at: Date(timeIntervalSince1970: 500)
        )
        let snapshot = try await service.synchronize(
            at: Date(timeIntervalSince1970: 600)
        )

        #expect(reader.receivedAnchors == [
            .empty,
            AppleHealthReplicaAnchors(
                workout: Data("workout-1".utf8),
                sleep: Data("sleep-1".utf8)
            ),
        ])
        #expect(snapshot.samples.workouts.map(\.kind) == [.running])
        #expect(snapshot.samples.sleep.isEmpty)
        #expect(snapshot.recordCount == 1)
        #expect(snapshot.lastSuccessfulSyncAt ==
            Date(timeIntervalSince1970: 600))
    }

    @Test @MainActor
    func healthKitPointSampleAdvancesAnchorInsteadOfReplayingForever()
        async throws
    {
        let repository = try makeAppleHealthReplicaTestRepository()
        let first = AppleHealthReplicaChangeBatch(
            workouts: [
                appleHealthWorkout(
                    id: UUID(),
                    start: 100,
                    end: 100
                ),
            ],
            deletedWorkoutIDs: [],
            workoutAnchor: Data("workout-point".utf8),
            sleep: [],
            deletedSleepIDs: [],
            sleepAnchor: Data("sleep-point".utf8)
        )
        let second = AppleHealthReplicaChangeBatch(
            workouts: [],
            deletedWorkoutIDs: [],
            workoutAnchor: Data("workout-next".utf8),
            sleep: [],
            deletedSleepIDs: [],
            sleepAnchor: Data("sleep-next".utf8)
        )
        let reader = ScriptedAppleHealthReplicaChangeReader(
            results: [.success(first), .success(second)]
        )
        let service = AppleHealthReplicaSyncService(
            reader: reader,
            repository: repository
        )

        _ = try await service.synchronize(
            at: Date(timeIntervalSince1970: 500)
        )
        _ = try await service.synchronize(
            at: Date(timeIntervalSince1970: 600)
        )

        #expect(reader.receivedAnchors == [
            .empty,
            AppleHealthReplicaAnchors(
                workout: Data("workout-point".utf8),
                sleep: Data("sleep-point".utf8)
            ),
        ])
        #expect(try repository.allSamples().recordCount == 1)
        #expect(try repository.anchors() == AppleHealthReplicaAnchors(
            workout: Data("workout-next".utf8),
            sleep: Data("sleep-next".utf8)
        ))
    }

    @Test @MainActor
    func queryFailureKeepsRowsAndAnchorsAtLastCommittedGeneration()
        async throws
    {
        let repository = try makeAppleHealthReplicaTestRepository()
        let first = AppleHealthReplicaChangeBatch(
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
        let reader = ScriptedAppleHealthReplicaChangeReader(
            results: [
                .success(first),
                .failure(ProbeError.queryFailed),
            ]
        )
        let service = AppleHealthReplicaSyncService(
            reader: reader,
            repository: repository
        )
        _ = try await service.synchronize(
            at: Date(timeIntervalSince1970: 500)
        )

        await #expect(throws: ProbeError.queryFailed) {
            _ = try await service.synchronize(
                at: Date(timeIntervalSince1970: 600)
            )
        }

        #expect(try repository.allSamples().recordCount == 1)
        #expect(try repository.allSamples().lastSuccessfulSyncAt ==
            Date(timeIntervalSince1970: 500))
        #expect(try repository.anchors() == AppleHealthReplicaAnchors(
            workout: Data("workout-1".utf8),
            sleep: Data("sleep-1".utf8)
        ))
    }

    @Test @MainActor
    func cancellationNeverAdvancesReplicaGeneration() async throws {
        let repository = try makeAppleHealthReplicaTestRepository()
        let reader = ScriptedAppleHealthReplicaChangeReader(
            results: [],
            suspends: true
        )
        let service = AppleHealthReplicaSyncService(
            reader: reader,
            repository: repository
        )
        let task = Task {
            try await service.synchronize(
                at: Date(timeIntervalSince1970: 500)
            )
        }
        while reader.requestCount == 0 {
            await Task.yield()
        }

        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(try repository.allSamples().recordCount == 0)
        #expect(try repository.anchors() == .empty)
    }

    private enum ProbeError: Error, Equatable {
        case queryFailed
    }
}

@MainActor
private final class ScriptedAppleHealthReplicaChangeReader:
    AppleHealthReplicaChangeReading
{
    var results: [Result<AppleHealthReplicaChangeBatch, Error>]
    var suspends: Bool
    var receivedAnchors: [AppleHealthReplicaAnchors] = []
    var requestCount = 0

    init(
        results: [Result<AppleHealthReplicaChangeBatch, Error>],
        suspends: Bool = false
    ) {
        self.results = results
        self.suspends = suspends
    }

    func replicaChanges(
        after anchors: AppleHealthReplicaAnchors
    ) async throws -> AppleHealthReplicaChangeBatch {
        requestCount += 1
        receivedAnchors.append(anchors)
        while suspends {
            try Task.checkCancellation()
            await Task.yield()
        }
        return try results.removeFirst().get()
    }
}
